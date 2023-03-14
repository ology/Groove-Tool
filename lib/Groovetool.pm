package Groovetool;

use lib map { "$ENV{HOME}/sandbox/$_/lib" } qw(Data-Dataset-ChordProgressions MIDI-Bassline-Walk MIDI-Util MIDI-Drummer-Tiny Music-Duration Music-Duration-Partition);

use Moo;
use strictures 2;
use Data::Dumper::Compact qw(ddc);
use MIDI::Drummer::Tiny ();
use MIDI::Util qw(set_chan_patch midi_format);
use Music::CreatingRhythms ();
use Music::Duration::Partition ();
use Music::Scales qw(get_scale_MIDI);
use Music::VoiceGen ();
use namespace::clean;

has filename => (is => 'ro', required => 1); # MIDI file name
has my_bpm   => (is => 'ro');
has repeat   => (is => 'ro');
has phrases  => (is => 'ro');
has dvolume  => (is => 'ro');
has reverb   => (is => 'ro');
has boctave  => (is => 'ro');
has bpatch   => (is => 'ro');
has bvolume  => (is => 'ro');
has bnote    => (is => 'ro');
has bscale   => (is => 'ro');
has bpool    => (is => 'ro');
has bweights => (is => 'ro');
has bgroups  => (is => 'ro');
has duel     => (is => 'ro');
has countin  => (is => 'ro');
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
        reverb => $self->reverb,
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
            $self->counter_part() if $self->duel;
            @phrases = ();
        }

        if ($part->{bars}) {
            $section = $key;
            $bars = $part->{bars};
            $bars-- if $part->{fillin};
            next;
        }
        else {
             $part->{bars} = $bars;
        }

        if ($part->{style} eq 'quarter') {
            $part->{factor} = 4;
            push @phrases, sub { $self->beat_part($part) };
        }
        elsif ($part->{style} eq 'eighth') {
            $part->{factor} = 8;
            push @phrases, sub { $self->beat_part($part) };
        }
        elsif ($part->{style} eq 'euclid') {
            push @phrases, sub { $self->euclidean_part($part) };
        }
        elsif ($part->{style} eq 'christoffel') {
            push @phrases, sub { $self->christoffel_part($part) };
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
        $self->counter_part() if $self->duel;
    }

    $self->drummer->write;

    return $self->msgs;
}

sub counter_part {
    my ($self) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my $bars = $self->drummer->bars;
    my $strike = $self->drummer->closed_hh;
    my $msg = "{ bars => $bars, strike => $strike, style => 'counter' }";
    my $msgs = $self->msgs;
    $self->msgs([ @$msgs, $msg ]);
    $self->drummer->count_in($bars);
}

sub beat_part {
    my ($self, $part) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my $pattern = '1' x $part->{factor};
    my $msgs = $self->msgs;
    $self->msgs([ @$msgs, ddc($part) ]);
    $self->drummer->pattern(
        instrument => $part->{strike},
        patterns   => [ ($pattern) x $part->{bars} ],
    );
}

sub euclidean_part {
    my ($self, $part) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my $pattern = euclidean_pattern($part);
    my $msgs = $self->msgs;
    $self->msgs([ @$msgs, ddc($part) ]);
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
    my ($self, $part) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my $pattern = christoffel_pattern($part);
    my $msgs = $self->msgs;
    $self->msgs([ @$msgs, ddc($part) ]);
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

sub fill_part {
    my ($self, $parts) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my %phrases;
    for my $key (@$parts) {
        my $part = $self->phrases->{$key};
        my $pattern;
        if ($part->{style} eq 'quarter' || $part->{style} eq 'eighth') {
            $pattern = '1' x $part->{factor};
        }
        elsif ($part->{style} eq 'euclid') {
            $pattern = euclidean_pattern($part);
        }
        elsif ($part->{style} eq 'christoffel') {
            $pattern = christoffel_pattern($part);
        }
        $phrases{ $part->{strike} } = [ $pattern ];
    }
    $self->drummer->add_fill(
        sub { $self->_fill($parts) },
        %phrases
    );
}

# TODO Make this generic!
sub _fill {
    my ($self, $parts) = @_;
    my $snare_ons = 1 + int rand($self->size / 2);
    my $hh = '0' x ($self->size / 2);
    (my $kick = $hh) =~ s/^0/1/;
    return {
        duration                  => $self->size,
        $self->drummer->closed_hh => $hh,
        $self->drummer->snare     => $self->drummer->euclidean($snare_ons, $self->size / 2),
        $self->drummer->kick      => $kick,
    };
}

sub bass {
    my ($self, $bars) = @_;

    return unless $self->bpatch > 0 && $self->bvolume;

    $bars ||= $self->drummer->bars;

    set_chan_patch($self->drummer->score, 1, $self->bpatch);

    $self->drummer->score->Volume($self->bvolume);

    my $pool    = [ split /[\s,-]+/, $self->bpool ];
    my $weights = [ split /[\s,-]+/, $self->bweights ];
    my $groups  = [ split /[\s,-]+/, $self->bgroups ];

    my $mdp = Music::Duration::Partition->new(
        size => $self->drummer->beats - 1,
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
