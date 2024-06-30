package Groovetool;

use if $ENV{USER} eq "gene", lib => map { "$ENV{HOME}/sandbox/$_/lib" } qw(Data-Dataset-ChordProgressions Music-Bassline-Generator MIDI-Util MIDI-Drummer-Tiny Music-Duration Music-Duration-Partition);

use Moo;
use strictures 2;
use Data::Dumper::Compact qw(ddc);
use MIDI::Drummer::Tiny ();
use MIDI::Util qw(set_chan_patch midi_format);
use Music::CreatingRhythms ();
use Music::Duration::Partition ();
use Music::RhythmSet::Util qw(upsize);
use Music::Scales qw(get_scale_MIDI);
use Music::VoiceGen ();
use namespace::clean;

has filename => (is => 'ro', required => 1); # MIDI file name
has my_bpm   => (is => 'ro');
has repeat   => (is => 'ro');
has my_duel  => (is => 'ro');
has countin  => (is => 'ro');
has phrases  => (is => 'ro');
has dvolume  => (is => 'ro');
has dreverb  => (is => 'ro');
has boctave  => (is => 'ro');
has bpatch   => (is => 'ro');
has bvolume  => (is => 'ro');
has bnote    => (is => 'ro');
has bscale   => (is => 'ro');
has bsize    => (is => 'ro');
has bpool    => (is => 'ro');
has bweights => (is => 'ro');
has bgroups  => (is => 'ro');
has size     => (is => 'ro', default => sub { 16 }); # changing this will make a mess usually
has msgs     => (is => 'rw', default => sub { [] }); # bucket for output messages
has drummer  => (is => 'lazy');
has creator  => (is => 'lazy');

sub _build_drummer {
    my ($self) = @_;
    my $d = MIDI::Drummer::Tiny->new(
        file   => $self->filename,
        bars   => 4 * $self->repeat,
        bpm    => $self->my_bpm,
        reverb => $self->dreverb,
        volume => $self->dvolume,
    );
    return $d;
}

sub _build_creator {
    my ($self) = @_;
    my $mcr = Music::CreatingRhythms->new;
    return $mcr;
}

sub process {
    my ($self) = @_;

    $self->drummer->count_in(1) if $self->countin;

    my $section; # top level
    my @phrases; # phrases to add to the score
    my $bars; # number of measures in a section

    for my $n (1 .. $self->repeat) {
        for my $key (sort keys $self->phrases->%*) {
            my $part = $self->phrases->{$key};

            if ($key =~ /^\d+$/ && @phrases) {
                push @phrases, sub { $self->bass($bars) };
                $self->drummer->sync(@phrases);
                if ($part->{fillin}) {
                    my @parts = grep { $_ =~ /^$key\_/ } sort keys $self->phrases->%*;
                    $self->drummer->sync(
                        sub { $self->fill_part(\@parts) },
                        sub { $self->bass(1) },
                    );
                }
                $self->counter_part() if $self->my_duel;
                @phrases = ();
            }

            if ($key =~ /^\d+$/ && $part->{bars}) {
                $section = $key;
                $bars = $part->{bars};
                $bars-- if $part->{fillin};
                next;
            }
            else {
                $part->{bars} = $bars;
            }

            if ($part->{style} eq 'euclid') {
                push @phrases, sub { $self->euclidean_part($part, $key) };
            }
            elsif ($part->{style} eq 'christoffel') {
                push @phrases, sub { $self->christoffel_part($part, $key) };
            }
            elsif ($part->{style} eq 'pfold') {
                push @phrases, sub { $self->pfold_part($part, $key) };
            }
        }

        if (@phrases) {
            push @phrases, sub { $self->bass($bars) };
            $self->drummer->sync(@phrases);
            if ($self->phrases->{$section}{fillin}) {
                my @parts = grep { $_ =~ /^$section\_/ } sort keys $self->phrases->%*;
                $self->drummer->sync(
                    sub { $self->fill_part(\@parts) },
                    sub { $self->bass(1) },
                );
            }
            $self->counter_part() if $self->my_duel;
            @phrases = ();
        }
    }

    $self->drummer->write;

    return $self->msgs;
}

sub counter_part {
    my ($self) = @_;
    $self->drummer->set_channel;
    $self->drummer->count_in($self->drummer->bars);
}

# XXX unused
sub beat_part {
    my ($self, $part, $key) = @_;
    $self->drummer->set_channel;
    my $pattern = $self->beat_pattern($part);
    $self->phrases->{$key}{pattern} = $pattern;
    $self->drummer->pattern(
        instrument => $part->{strike},
        patterns   => [ ($pattern) x $part->{bars} ],
    );
}
sub beat_pattern {
    my ($self, $part) = @_;
    my $sequence = [ ('1') x $part->{factor} ];
    $sequence = upsize($sequence, $self->size);
    $sequence = $self->creator->rotate_n($part->{shift}, $sequence)
        if $part->{shift};
    return join '', @$sequence;
}

sub euclidean_part {
    my ($self, $part, $key) = @_;
    $self->drummer->set_channel;
    my $pattern = $self->euclidean_pattern($part);
    $self->phrases->{$key}{pattern} = $pattern;
    $self->drummer->pattern(
        instrument => $part->{strike},
        patterns   => [ ($pattern) x $part->{bars} ],
    );
}
sub euclidean_pattern {
    my ($self, $part) = @_;
    my $sequence = $self->creator->euclid($part->{onsets}, $self->size);
    $sequence = $self->creator->rotate_n($part->{shift}, $sequence)
        if $part->{shift};
    return join '', @$sequence;
}

sub christoffel_part {
    my ($self, $part, $key) = @_;
    $self->drummer->set_channel;
    my $pattern = $self->christoffel_pattern($part);
    $self->phrases->{$key}{pattern} = $pattern;
    $self->drummer->pattern(
        instrument => $part->{strike},
        patterns   => [ ($pattern) x $part->{bars} ],
    );
}
sub christoffel_pattern {
    my ($self, $part) = @_;
    my $sequence = $self->creator->chsequl(
        $part->{case},
        $part->{numerator}, $part->{denominator},
        $self->size
    );
    $sequence = $self->creator->rotate_n($part->{shift}, $sequence)
        if $part->{shift};
    return join '', @$sequence;
}

sub pfold_part {
    my ($self, $part, $key) = @_;
    $self->drummer->set_channel;
    my $pattern = $self->pfold_pattern($part);
    $self->phrases->{$key}{pattern} = $pattern;
    $self->drummer->pattern(
        instrument => $part->{strike},
        patterns   => [ ($pattern) x $part->{bars} ],
    );
}
sub pfold_pattern {
    my ($self, $part) = @_;
    my $sequence = $self->creator->pfold(
        $self->size,
        $part->{fsize},
        $part->{ffunction},
    );
    $sequence = $self->creator->rotate_n($part->{shift}, $sequence)
        if $part->{shift};
    return join '', @$sequence;
}

sub fill_part {
    my ($self, $parts) = @_;
    $self->drummer->set_channel;
    my %phrases;
    for my $key (@$parts) {
        my $part = $self->phrases->{$key};
        my $pattern;
        if ($part->{style} eq 'euclid') {
            $pattern = $self->euclidean_pattern($part);
        }
        elsif ($part->{style} eq 'christoffel') {
            $pattern = $self->christoffel_pattern($part);
        }
        elsif ($part->{style} eq 'pfold') {
            $pattern = $self->pfold_pattern($part);
        }
        $phrases{ $part->{strike} } = [ $pattern ];
    }
    $self->drummer->add_fill(
        sub { $self->_fill(\%phrases) },
        %phrases
    );
}

sub _fill {
    my ($self, $phrases) = @_;
    my $parts = { %$phrases };
    for (keys %$parts) {
        if ($_ == $self->drummer->acoustic_snare || $_ == $self->drummer->electric_snare) {
            my $onsets = 1 + int rand $self->size; # XXX this is sometimes lame
            $parts->{$_} = $self->euclidean_pattern({ onsets => $onsets });
        }
        elsif ($_ == $self->drummer->pedal_hh || $_ == $self->drummer->acoustic_bass || $_ == $self->drummer->electric_bass) {
            $parts->{$_} = $parts->{$_}[0];
        }
        else {
            $parts->{$_} = '0' x $self->size;
        }
    }
    return {
        duration => $self->size,
        %$parts
    };
}

sub bass {
    my ($self, $bars) = @_;

    return unless $self->bpatch > 0 && $self->bvolume;

    $bars ||= $self->drummer->bars;

    set_chan_patch($self->drummer->score, 0, $self->bpatch);

    $self->drummer->set_volume($self->bvolume);

    my $pool    = [ split /[\s,-]+/, $self->bpool ];
    my $weights = [ split /[\s,-]+/, $self->bweights ];
    my $groups  = [ split /[\s,-]+/, $self->bgroups ];

    my $mdp = Music::Duration::Partition->new(
        size => $self->bsize,
        pool => $pool,
        $self->bweights ? (weights => $weights) : (),
        $self->bgroups  ? (groups => $groups)   : (),
    );
    my @motifs = map { $mdp->motif } 1 .. 2;

    my @pitches = get_scale_MIDI($self->bnote, $self->boctave, $self->bscale);

    my $voice = Music::VoiceGen->new(
        pitches   => \@pitches,
        intervals => [qw/-4 -3 -2 2 3 4/],
    );

    my @notes1 = map { $voice->rand } $motifs[0]->@*;

    for my $i (1 .. $bars) {
        if ($i % 2) {
            $mdp->add_to_score($self->drummer->score, $motifs[0], \@notes1);
        }
        else {
            my @notes2 = map { $voice->rand } $motifs[1]->@*;
            $mdp->add_to_score($self->drummer->score, $motifs[1], \@notes2);
        }

        $self->drummer->rest($self->drummer->quarter);
    }
}

1;
