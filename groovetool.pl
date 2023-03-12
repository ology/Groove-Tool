#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

use File::Find::Rule ();
use Time::HiRes qw(time);

use lib 'lib';
use Groovetool ();

use constant MIDI_GLOB  => '*.mid';
use constant TIME_LIMIT => 60 * 60 * 24; # 1 day

get '/' => sub ($c) {
  my $submit  = $c->param('submit')  || 0;
  my $my_bpm  = $c->param('my_bpm')  || 90; # 1 - ?
  my $repeat  = $c->param('repeat')  || 1; # number of times to repeat
  my $euclid  = $c->param('euclid')  // '2,3 3,2'; # "kick,snare" onsets
  my $eumax   = $c->param('eumax')   // 4; # number of random grooves to generate unless given euclids
  my $christo = $c->param('christo') // 'u-11-5,u-11-5 l-11-5,l-11-5'; # "kick,snare" onsets
  my $chmax   = $c->param('chmax')   // 4; # number of random grooves to generate unless given christoffels
  my $dvolume = $c->param('dvolume') // 100; # 0 - 127
  my $reverb  = $c->param('reverb')  // 15; # 0 - 127
  my $boctave = $c->param('boctave') || 1; # 1, 2, ...?
  my $bpatch  = $c->param('bpatch')  || 35; # 0 - 127 and -1 = off
  my $bvolume = $c->param('bvolume') // 90; # 0 - 127
  my $bnote   = $c->param('bnote')   // 'A'; # C, C#, Db, D, ... B
  my $bscale  = $c->param('bscale')  // 'pminor'; # see Music::Scales
  my $pool    = $c->param('pool')    || 'qn en sn'; # MIDI-Perl note durations
  my $weights = $c->param('weights') // '1 1 1'; # weights of the note duration pool
  my $groups  = $c->param('groups')  // '1 2 4'; # groupings of the pool notes
  my $duel    = $c->param('duel')    || 0; # alternate with the hihat-only, counterpart section
  my $countin = $c->param('countin') || 0; # play 4 hihat notes to start things off

  _purge($c); # purge defunct midi files

  my $filename = '';
  my $msgs = [];

  if ($submit) {
    $filename = '/' . time() . '.mid';

    my $groove = Groovetool->new(
      filename => 'public' . $filename,
      my_bpm   => $my_bpm,
      repeat   => $repeat,
      euclid   => $euclid,
      dvolume  => $dvolume,
      reverb   => $reverb,
      boctave  => $boctave,
      bpatch   => $bpatch,
      bvolume  => $bvolume,
      bnote    => $bnote,
      bscale   => $bscale,
      bpool    => $pool,
      bweights => $weights,
      bgroups  => $groups,
      eumax    => $eumax,
      duel     => $duel,
      countin  => $countin,
    );

    $msgs = $groove->process;
  }

  $c->render(
    template => 'index',
    msgs     => $msgs,
    filename => $filename,
    my_bpm   => $my_bpm,
    repeat   => $repeat,
    euclid   => $euclid,
    dvolume  => $dvolume,
    reverb   => $reverb,
    boctave  => $boctave,
    bpatch   => $bpatch,
    bvolume  => $bvolume,
    bnote    => $bnote,
    bscale   => $bscale,
    pool     => $pool,
    weights  => $weights,
    groups   => $groups,
    eumax    => $eumax,
    duel     => $duel,
    countin  => $countin,
  );
} => 'index';

get '/help' => sub ($c) {
  $c->render(
    template => 'help',
  );
} => 'help';

app->log->level('info');

app->start;

sub _purge {
  my ($c) = @_;
  my $threshold = time() - TIME_LIMIT;
  my @files = File::Find::Rule
    ->file()
    ->name(MIDI_GLOB)
    ->ctime("<$threshold")
    ->in('public');
  for my $file (@files) {
    $c->app->log->info("Removing old file: $file");
    unlink $file;
  }
}

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Groove Generator';

<div class="row">
  <label for="my_bpm">BPM:</label>
  <input type="number" class="form-control form-control-sm" id="my_bpm" name="my_bpm" min="1" max="200" value="<%= $my_bpm %>" title="1 to 200 beats per minute">
</div>

<div class="row">
  <div class="col-6">

<p></p>

<form>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="my_bpm">BPM:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="my_bpm" name="my_bpm" min="1" max="200" value="<%= $my_bpm %>" title="1 to 200 beats per minute">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="repeat">Repeat:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="repeat" name="repeat" min="1" max="64" value="<%= $repeat %>" title="1 to 64 repeats">
      </div>
    </div>
  </div>

  <div class="row">
    <div class="col">
    </div>
    <div class="col">
      <div class="form-check form-check-inline">
        <input class="form-check-input" type="checkbox" id="countin" name="countin" <%= $countin ? 'checked' : '' %> title="Play 4 hihat notes to start things off">
        <label class="form-check-label" for="countin">Count-in</label>
      </div>
    </div>
  </div>

  <div class="row">
    <div class="col">
    </div>
    <div class="col">
      <div class="form-check form-check-inline">
        <input class="form-check-input" type="checkbox" id="duel" name="duel" <%= $duel ? 'checked' : '' %> title="alternate with a hihat-only, 'counterpart' section">
        <label class="form-check-label" for="duel">Duel</label>
      </div>
    </div>
  </div>

  <p></p>

  <div class="row">
    <div class="col">
    </div>
    <div class="col">
      <button type="button" class="btn btn-outline-dark btn-sm btn-block" data-toggle="collapse" data-target="#bassSettings">Bass Settings</button>
    </div>
  </div>

<div class="collapse" id="bassSettings">

  <p></p>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="bnote">Note:</label>
      </div>
      <div class="col">
        <input type="text" class="form-control form-control-sm" id="bnote" name="bnote" value="<%= $bnote %>" maxlength="2" title="C, C#, Db, D, ... B bass scale starting note">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="bscale">Scale:</label>
      </div>
      <div class="col">
        <input type="text" class="form-control form-control-sm" id="bscale" name="bscale" value="<%= $bscale %>" title="bass scale name">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="bpatch">Patch:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="bpatch" name="bpatch" min="0" max="127" value="<%= $bpatch %>" title="0 to 127 defining the bass patch">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="bvolume">Volume:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="bvolume" name="bvolume" min="0" max="127" value="<%= $bvolume %>" title="0 to 127 defining the bass volume">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="boctave">Octave:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="boctave" name="boctave" min="1" max="4" value="<%= $boctave %>" title="Bass octave from 1 to 4">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="pool">Pool:</label>
      </div>
      <div class="col">
        <input type="text" class="form-control form-control-sm" id="pool" name="pool" value="<%= $pool %>" title="Allowed bass durations" aria-describedby="poolHelp">
        <small id="poolHelp" class="form-text text-muted">qn = quarter note, ten = triplet eighth, etc.</small>
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="weights">Weights:</label>
      </div>
      <div class="col">
        <input type="text" class="form-control form-control-sm" id="weights" name="weights" value="<%= $weights %>" title="Weights of bass durations" aria-describedby="weightsHelp">
        <small id="weightsHelp" class="form-text text-muted">Weights of each pool duration</small>
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="groups">Groups:</label>
      </div>
      <div class="col">
        <input type="text" class="form-control form-control-sm" id="groups" name="groups" value="<%= $groups %>" title="Groupings of bass durations" aria-describedby="groupsHelp">
        <small id="groupsHelp" class="form-text text-muted">Groups of pool durations (e.g. ten = 3)</small>
      </div>
    </div>
  </div>

</div>

<p></p>

  <div class="row">
    <div class="col">
    </div>
    <div class="col">
      <button type="button" class="btn btn-outline-dark btn-sm btn-block" data-toggle="collapse" data-target="#drumSettings">Drum Settings</button>
    </div>
  </div>

<div class="collapse" id="drumSettings">

  <p></p>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="euclid">Euclid:</label>
      </div>
      <div class="col">
        <input type="text" class="form-control form-control-sm" id="euclid" name="euclid" value="<%= $euclid %>" title="Space-separated kick,snare onset list" aria-describedby="euclidHelp">
        <small id="euclidHelp" class="form-text text-muted">Form: &lt;kick_onsets>,&lt;snare_onsets></small>
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="eumax">Max:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="eumax" name="eumax" min="0" max="16" value="<%= $eumax %>" title="number of random grooves to generate unless given a euclid list">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="dvolume">Volume:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="dvolume" name="dvolume" min="0" max="127" value="<%= $dvolume %>" title="0 to 127 defining the drums volume">
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="row">
      <div class="col">
        <label for="reverb">Reverb:</label>
      </div>
      <div class="col">
        <input type="number" class="form-control form-control-sm" id="reverb" name="reverb" min="0" max="127" value="<%= $reverb %>" title="0 to 127 drum reverb amount">
      </div>
    </div>
  </div>

</div>

  <p></p>

  <input type="submit" class="btn btn-sm btn-primary" name="submit" value="Generate">

</form>

  </div>
  <div class="col-6">

% if ($filename) {
    <p></p>
    MIDI: &nbsp;
    <a href="#" onClick="MIDIjs.play('<%= $filename %>');" title="Play MIDI"><i class="fa-solid fa-play"></i></a>
    &nbsp; | &nbsp;
    <a href="#" onClick="MIDIjs.stop();" title="Stop MIDI"><i class="fa-solid fa-stop"></i></a>
    &nbsp; | &nbsp;
    <a href="<%= $filename %>" title="Download MIDI"><i class="fa-solid fa-download"></i></a>
    <p></p>
    <ol>
%   for my $msg (@$msgs) {
      <li><%== $msg %></li>
%   }
    </ol>
% }

  </div>
</div>

@@ help.html.ep
% layout 'default';
% title 'Help!';

<p>For a list of the available patches, please see <a href="https://www.midi.org/specifications-old/item/gm-level-1-sound-set">this page</a>.</p>
<p>Many settings are self explanatory, but the <b>bass</b> deserves a bit of attention.</p>
<p>The <b>octave</b> is most naturally either <b>1</b> or <b>2</b>. Different patches sound ok at the lowest octave. Some sound better the next one up.</p>
<p><b>Motifs</b> are the number of bass phrases or "figures." These are chosen at random during the progression. The more there are, the more random the bassline is.</p>
<p>The <b>pool</b> is the required set of note durations that can happen. These are in "MIDI-Perl" format, where "hn" is a half-note, and "ten" is a triplet eighth-note, etc.</p>
<p><b>Weights</b> are the optional probabilities that the corresponding pool entries will be chosen.</p>
<p><b>Groups</b> are the optional indications for how many times to try to repeat a corresponding duration in succession.</p>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="/css/fontawesome.css" rel="stylesheet">
    <link href="/css/solid.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" integrity="sha384-GLhlTQ8iRABdZLl6O3oVMWSktQOp6b7In1Zl3/Jr59b6EGGoI1aFkw7cmDA6j6gD" crossorigin="anonymous">
    <script src='//www.midijs.net/lib/midi.js'></script>
    <script src="https://cdn.jsdelivr.net/npm/jquery@3.5.1/dist/jquery.slim.min.js" integrity="sha384-DfXdz2htPH0lsSSs5nCTpuj/zy4C+OGpamoFVy38MVBnE+IbbVYUew+OrCXaRkfj" crossorigin="anonymous"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/js/bootstrap.bundle.min.js" integrity="sha384-w76AqPfDkMBDXo30jS1Sgez6pr3x5MlQ1ZAGC+nuZB+EYdgRZgiwxhTBTkF7CXvN" crossorigin="anonymous"></script>
    <title><%= title %></title>
    <style>
      .padpage {
        padding-top: 10px;
      }
      .small {
        font-size: small;
        color: darkgrey;
      }
    </style>
  </head>
  <body>
    <div class="container padpage">
      <h3><a href="/"><%= title %></a></h3>
      <%= content %>
      <p></p>
      <div id="footer" class="small">
        <hr>
        Built by <a href="http://gene.ology.net/">Gene</a>
        with <a href="https://www.perl.org/">Perl</a> and
        <a href="https://mojolicious.org/">Mojolicious</a>
        | <a href="/help">Help!</a>
      </div>
    </div>
  </body>
</html>
