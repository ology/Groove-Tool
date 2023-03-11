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

has filename   => (is => 'ro', required => 1); # MIDI file name
has my_bpm     => (is => 'ro');
has euclid     => (is => 'ro');
has max        => (is => 'ro');
has repeat     => (is => 'ro');
has dvolume    => (is => 'ro');
has reverb     => (is => 'ro');
has boctave    => (is => 'ro');
has bpatch     => (is => 'ro');
has bvolume    => (is => 'ro');
has bnote      => (is => 'ro');
has bscale     => (is => 'ro');
has my_pool    => (is => 'ro');
has my_weights => (is => 'ro');
has my_groups  => (is => 'ro');
has duel       => (is => 'ro');
has countin    => (is => 'ro');
has verbose    => (is => 'ro');
has size       => (is => 'ro', default => sub { 16 }); # changing this will make a mess usually
has msgs       => (is => 'rw', default => sub { [] }); # bucket for output messages
has drummer    => (is => 'lazy');

sub _build_drummer {
    my ($self) = @_;
    my $d = MIDI::Drummer::Tiny->new(
        file   => $self->filename,
        bars   => 4 * $self->phrases,
        bpm    => $self->my_bpm,
        reverb => $self->reverb,
        volume => $self->dvolume,
    );
    return $d;
}

sub process {
    my ($self) = @_;

    $self->drummer->sync(
        sub { drums($self) },
        sub { bass($self) },
    );

    $self->drummer->write;

    return $self->msgs;
}

sub drums {
    my ($self) = @_;

    return if $self->do_drums && $self->dvolume;

    my $bars = $self->drummer->bars * $self->repeat;

    ...;
}

sub bass {
    my ($self, $bars) = @_;

    return unless $self->bpatch > 0 && $self->bvolume;

    $bars ||= $self->drummer->bars;

    set_chan_patch($self->drummer->score, 1, $self->bpatch);

    $self->drummer->score->Volume($self->bvolume);

    my $pool    = [ split /[\s,-]+/, $self->my_pool ];
    my $weights = [ split /[\s,-]+/, $self->my_weights ];
    my $groups  = [ split /[\s,-]+/, $self->my_groups ];

    my $mdp = Music::Duration::Partition->new(
        size => $self->drummer->beats - 1,
        pool => $pool,
        $self->my_weights ? (weights => $weights) : (),
        $self->my_groups  ? (groups => $groups)   : (),
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
