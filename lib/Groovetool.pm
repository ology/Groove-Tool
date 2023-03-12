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

has filename  => (is => 'ro', required => 1); # MIDI file name
has my_bpm    => (is => 'ro');
has repeat    => (is => 'ro');
has euclid    => (is => 'ro');
has eumax     => (is => 'ro');
has christo   => (is => 'ro');
has chmax     => (is => 'ro');
has dvolume   => (is => 'ro');
has reverb    => (is => 'ro');
has boctave   => (is => 'ro');
has bpatch    => (is => 'ro');
has bvolume   => (is => 'ro');
has bnote     => (is => 'ro');
has bscale    => (is => 'ro');
has bpool     => (is => 'ro');
has bweights  => (is => 'ro');
has bgroups   => (is => 'ro');
has duel      => (is => 'ro');
has countin   => (is => 'ro');
has size      => (is => 'ro', default => sub { 16 }); # changing this will make a mess usually
has rotate_by => (is => 'ro', default => sub { 4 });  # number of steps to rotate (snare usually)
has msgs      => (is => 'rw', default => sub { [] }); # bucket for output messages
has drummer   => (is => 'lazy');

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

sub process {
    my ($self) = @_;

    my $bars = $self->drummer->bars;# * $self->repeat;

    my $grooves = $self->init_grooves;

    $self->drummer->count_in(1) if $self->countin;

    for my $groove (@$grooves) {
        $self->euclidean_part($groove->{snare}, $groove->{kick});

        $self->counterpart() if $self->duel;
    }

    $self->drummer->write;

    return $self->msgs;
}

sub init_grooves {
    my ($self) = @_;

    my $euclid = [ split /\s+/, $self->euclid ];

    # initialize the kick and snare onsets
    my @grooves;
    for my $item (@$euclid) {
        my ($kick, $snare) = split /,/, $item;
        push @grooves, {
            kick  => $kick,
            snare => $snare,
        };
    }
    unless (@grooves) {
        for my $i (1 .. $self->eumax) {
            my $kick = $self->kick_onsets;
            push @grooves, {
                kick  => $kick,
                snare => $self->snare_onsets(0, $kick),
            };
        }
        # slower grooves go first
        @grooves = sort { $a->{kick} <=> $b->{kick} || $a->{snare} <=> $b->{snare} } @grooves;
    }

    my @msgs; # Message accumulator
    push @msgs, map { ddc($_) } @grooves;
    $self->msgs(\@msgs);

    return \@grooves;
}

sub counterpart {
    my ($self) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    $self->drummer->count_in($self->drummer->bars);
}

sub euclidean_part {
    my ($self, $snare_ons, $kick_ons) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my $bars = $self->drummer->bars - 1;
    my $hh = '1' x ($self->size / 2);
    $self->drummer->sync(
        sub { $self->drummer->pattern( instrument => $self->drummer->closed_hh, patterns => [ ($hh) x $bars ] ) },
        sub { $self->drummer->pattern( instrument => $self->drummer->snare,     patterns => [ ($self->rotate_sequence($snare_ons)) x $bars ] ) },
        sub { $self->drummer->pattern( instrument => $self->drummer->kick,      patterns => [ ($self->drummer->euclidean($kick_ons, $self->size)) x $bars ] ) },
        sub { $self->bass($bars) },
    );
    $self->drummer->sync(
        sub { $self->fill($snare_ons, $kick_ons) },
        sub { $self->bass(1) },
    );
}

sub fill {
    my ($self, $snare_onset, $kick_onset) = @_;
    set_chan_patch($self->drummer->score, 9, 0);
    my $hh = '1' x ($self->size / 2);
    $self->drummer->add_fill(
        sub { $self->_fill },
        $self->drummer->closed_hh => [ $hh ],
        $self->drummer->snare     => [ $self->rotate_sequence($snare_onset) ],
        $self->drummer->kick      => [ $self->drummer->euclidean($kick_onset, $self->size) ],
    );
}

sub _fill {
    my ($self) = @_;
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

sub rotate_sequence {
    my ($self, $onsets) = @_;
    my $mcr = Music::CreatingRhythms->new;
    my $sequence = $mcr->euclid($onsets, $self->size);
    $sequence = $mcr->rotate_n($self->rotate_by, $sequence);
    my $sequence_string = join '', @$sequence;
    return $sequence_string;
}

sub kick_onsets {
    my ($self, $onsets) = @_;
    unless ($onsets) {
        $onsets = $self->rand_onset;
        while ($onsets < 3) {
            $onsets = $self->rand_onset;
        }
    }
    return $onsets;
}

sub snare_onsets {
    my ($self, $onsets, $kick) = @_;
    unless ($onsets) {
        $onsets = $self->rand_onset;
        while ($onsets >= $kick) {
            $onsets = $self->rand_onset;
        }
    }
    return $onsets;
}

sub rand_onset {
    my ($self, $n) = @_;
    $n ||= $self->size / 2;
    return 1 + int rand($n - 1);
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
