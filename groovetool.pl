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
  my $euclid  = $c->param('euclid')  // '2,3 3,2'; # onsets
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

<form>

<input type="submit" class="btn btn-sm btn-primary" name="submit" value="Generate">

% if ($filename) {
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

<p></p>
<div>
  <button type="button" class="btn btn-outline-dark btn-sm" data-bs-toggle="collapse" data-bs-target="#generalSettings">General Settings</button>
  <button type="button" class="btn btn-outline-dark btn-sm" data-bs-toggle="collapse" data-bs-target="#drumSettings">Drum Settings</button>
  <button type="button" class="btn btn-outline-dark btn-sm" data-bs-toggle="collapse" data-bs-target="#bassSettings">Bass Settings</button>
  <button type="button" id="btnAddPart" class="btn btn-success btn-sm">Add Part</button>
</div>

<div class="collapse" id="generalSettings">
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="my_bpm" name="my_bpm" min="1" max="200" value="<%= $my_bpm %>" title="1 to 200 beats per minute">
    <label for="my_bpm">BPM</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="repeat" name="repeat" min="1" max="64" value="<%= $repeat %>" title="1 to 64 repeats">
    <label for="repeat">Repeat</label>
  </div>
  <p></p>
  <div class="d-inline-flex align-items-center">
    <div class="form-check form-check-inline">
      <input class="form-check-input" type="checkbox" id="countin" name="countin" <%= $countin ? 'checked' : '' %> title="Play 4 hihat notes to start things off">
      <label class="form-check-label" for="countin">Count-in</label>
    </div>
    <div class="form-check form-check-inline">
      <input class="form-check-input" type="checkbox" id="duel" name="duel" <%= $duel ? 'checked' : '' %> title="alternate with a hihat-only, 'counterpart' section">
      <label class="form-check-label" for="duel">Duel</label>
    </div>
  </div>
</div>

<div class="collapse" id="drumSettings">
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="eumax" name="eumax" min="0" max="16" value="<%= $eumax %>" title="number of random grooves to generate unless given a euclid list">
    <label for="eumax">Max</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="text" class="form-control form-control-sm" id="euclid" name="euclid" value="<%= $euclid %>" title="Space-separated kick,snare onset list" aria-describedby="euclidHelp">
    <label for="euclid">Euclid</label>
    <small id="euclidHelp" class="form-text text-muted">kick_onsets,snare_onsets</small>
  </div>
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="dvolume" name="dvolume" min="0" max="127" value="<%= $dvolume %>" title="0 to 127 defining the drums volume">
    <label for="dvolume">Volume</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="reverb" name="reverb" min="0" max="127" value="<%= $reverb %>" title="0 to 127 drum reverb amount">
    <label for="reverb">Reverb</label>
  </div>
</div>

<div class="collapse" id="bassSettings">
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="text" class="form-control form-control-sm" id="bnote" name="bnote" value="<%= $bnote %>" maxlength="2" title="C, C#, Db, D, ... B bass scale starting note">
    <label for="bnote">Note</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="text" class="form-control form-control-sm" id="bscale" name="bscale" value="<%= $bscale %>" title="bass scale name">
    <label for="bscale">Scale</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="bpatch" name="bpatch" min="0" max="127" value="<%= $bpatch %>" title="0 to 127 defining the bass patch">
    <label for="bpatch">Patch</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="bvolume" name="bvolume" min="0" max="127" value="<%= $bvolume %>" title="0 to 127 defining the bass volume">
    <label for="bvolume">Volume</label>
  </div>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="number" class="form-control form-control-sm" id="boctave" name="boctave" min="1" max="4" value="<%= $boctave %>" title="Bass octave from 1 to 4">
    <label for="boctave">Octave</label>
  </div>
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="text" class="form-control form-control-sm" id="pool" name="pool" value="<%= $pool %>" title="Allowed bass durations" aria-describedby="poolHelp">
    <label for="pool">Pool</label>
    <small id="poolHelp" class="form-text text-muted">qn = quarter note, ten = triplet eighth, etc.</small>
  </div>
  <br>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="text" class="form-control form-control-sm" id="weights" name="weights" value="<%= $weights %>" title="Weights of bass durations" aria-describedby="weightsHelp">
    <label for="weights">Weights</label>
    <small id="weightsHelp" class="form-text text-muted">pool duration weights</small>
  </div>
  <br>
  <div class="form-floating d-inline-flex align-items-center">
    <input type="text" class="form-control form-control-sm" id="groups" name="groups" value="<%= $groups %>" title="Groupings of bass durations" aria-describedby="groupsHelp">
    <label for="groups">Groups</label>
    <small id="groupsHelp" class="form-text text-muted">pool duration groups (e.g. ten = 3)</small>
  </div>
</div>

<div class="parts"></div>
<div class="defaultPart d-none">
    <p></p>
    <div class="form-floating d-inline-flex align-items-center">
      <select id="strike" class="form-select" aria-label="Drum strike">
        <option value="44">Pedal Hihat</option>
        <option value="42">Closed Hihat</option>
        <option value="46">Open Hihat</option>
        <option value="37">Side Stick</option>
        <option value="38">Acoustic Snare</option>
        <option value="40">Electric Snare</option>
        <option value="35">Bass Drum</option>
        <option value="36">Electric Drum</option>
      </select>
      <label for="strike">Strike</label>
    </div>
    <div class="form-floating d-inline-flex align-items-center">
      <input type="number" class="form-control form-control-sm" id="shift" name="shift" min="0" max="15" value="<%= '$shift' %>" title="Shift sequence by N">
      <label for="shift">Shift by</label>
    </div>
    <p></p>
    <div class="d-inline-flex align-items-center">
      <input class="form-check-input" type="radio" name="style" id="quarter_style" value="" title="Simple quarter note">
      &nbsp;
      &nbsp;
      <label for="quarter_style">Quarter notes</label>
    </div>
    &nbsp;
    &nbsp;
    &nbsp;
    <div class="d-inline-flex align-items-center">
      <input class="form-check-input" type="radio" name="style" id="eighth_style" value="" title="Simple eighth notes">
      &nbsp;
      &nbsp;
      <label for="eighth_style">Eighth notes</label>
    </div>
    <p></p>
    <input class="form-check-input" type="radio" name="style" id="euclid_style" value="" title="Euclidean word">
    &nbsp;
    <div class="form-floating d-inline-flex align-items-center">
      <input type="number" class="form-control form-control-sm" id="onsets" name="onsets" min="1" max="16" value="<%= '$onsets' %>" title="Number of Euclidean onsets">
      <label for="onsets">Euclidean onsets</label>
    </div>
    <p></p>
    <input class="form-check-input" type="radio" name="style" id="christo_style" value="" title="Christoffel word">
    &nbsp;
    <div class="form-floating d-inline-flex align-items-center">
      <input type="number" class="form-control form-control-sm" id="numerator" name="numerator" min="1" max="16" value="<%= '$numerator' %>" title="Christoffel numerator">
      <label for="numerator">Numerator</label>
    </div>
    <div class="form-floating d-inline-flex align-items-center">
      <input type="number" class="form-control form-control-sm" id="denominator" name="denominator" min="1" max="16" value="<%= '$denominator' %>" title="Christoffel denominator">
      <label for="denominator">Denominator</label>
    </div>
    <div class="form-floating d-inline-flex align-items-center">
      <select id="up_low" class="form-select" aria-label="Upper or lower word" title="Upper or lower Christoffel word">
        <option value="u">Upper</option>
        <option value="l">Lower</option>
      </select>
      <label for="up_low">Case</label>
    </div>
    <p></p>
    <button type="button" class="btnRemovePart btn btn-danger btn-sm">Remove Part</button>
</div>

</form>

<script>
$(document).ready(function () {
  var i = 0;
  $("#btnAddPart").click(function () {
    i++;
    var $appendItem = $(".defaultPart").html();
    $("<div />", { "class":"part", id:"part_" + i }).append(
      $($appendItem)).appendTo('.parts');
  });
  $("body").on("click", ".btnRemovePart", function() {
    $(this).closest(".part").remove();
  });
});
</script>

@@ help.html.ep
% layout 'default';
% title 'Help!';

<p>TBD...</p>

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
