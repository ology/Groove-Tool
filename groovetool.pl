#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

use lib map { "$ENV{HOME}/sandbox/$_/lib" } qw(MIDI-Util); # local author libs

use Data::Dumper::Compact qw(ddc);
use File::Find::Rule ();
use MIDI::Util qw(midi_dump);
use Storable qw(retrieve nstore);
use Time::HiRes qw(time);

use lib 'lib';
use Groovetool ();

use constant MIDI_GLOB  => '*.mid';
use constant TIME_LIMIT => 60 * 60 * 24; # 1 day

get '/' => sub ($c) {
  my $submit   = $c->param('generate') || 0;
  my $my_bpm   = $c->param('my_bpm')   || 60; # 1 - ?
  my $repeat   = $c->param('repeat')   || 1; # number of times to repeat
  my $my_duel  = $c->param('my_duel')  || 0; # alternate with the hihat-only, counterpart section
  my $countin  = $c->param('countin')  || 0; # play 4 hihat notes to start things off
  my $loadg    = $c->param('loadg')    || ''; # load the given groove
  my $saveg    = $c->param('saveg')    || ''; # save the current groove
  my $removeg  = $c->param('removeg')  || ''; # remove the current groove
  my $section  = $c->param('section')  || 0; # current section number
  my $dvolume  = $c->param('dvolume')  // 100; # 0 - 127
  my $dreverb  = $c->param('dreverb')  // 15; # 0 - 127
  my $boctave  = $c->param('boctave')  || 1; # 1, 2, ...?
  my $bpatch   = $c->param('bpatch')   // 35; # 0 - 127 and -1 = off
  my $bvolume  = $c->param('bvolume')  // 90; # 0 - 127
  my $bnote    = $c->param('bnote')    || 'A'; # C, C#, Db, D, ... B
  my $bscale   = $c->param('bscale')   || 'pminor'; # see Music::Scales
  my $bsize    = $c->param('bsize')    || 3; # number of beats in a bass phrase
  my $bpool    = $c->param('bpool')    || 'qn en sn'; # MIDI-Perl note durations
  my $bweights = $c->param('bweights') // '1 1 1'; # weights of the note duration pool
  my $bgroups  = $c->param('bgroups')  // '1 2 4'; # groupings of the pool notes

  my $path = 'public/grooves';
  my $filename = '';
  my $msgs = [];

  my %phrases;
  for my $param ($c->req->params->names->@*) {
    next if $param =~ /^bit/;
    next unless $c->param($param);
    if ($param =~ /^([a-z]+)_([\d_]+)$/) {
      my $key   = $1;
      my $order = $2;
      $phrases{$order}->{$key} = $c->param($param);
    }
  }
  for my $key (sort keys %phrases) {
    next if $key =~ /^bit/;
    next unless $key =~ /^\d+$/;
    my $parts = grep { $_ =~ /^$key\_/ } keys %phrases;
    $phrases{$key}->{parts} = $parts;
  }

  my $kit = midi_dump('percussion2notenum');

  _purge($c); # purge defunct midi files

  # remove, save or load grooves
  if ($removeg) {
    my $name = $path . $removeg;
    unlink $name or warn "Can't unlink $name: $!\n";
    %phrases = ();
    # flash success/fail?
  }
  if ($saveg) {
    $filename = $saveg;
    my $name = $path . $filename;
    nstore(\%phrases, $name);
    # flash success/fail?
  }
  if ($loadg) {
    $filename = "/$loadg";
    my $name = $path . $filename;
    %phrases = %{ retrieve $name };
    $section = grep { $_ =~ /^\d+$/ } keys %phrases;
    # flash success/fail?
  }
  # gather saved grooves
  my @grooves = File::Find::Rule
    ->file()
    ->name('*.mid')
    ->in($path);
  for (@grooves) {
    $_ =~ s/^$path\/([\d.]+\.mid)$/$1/;
  }

  if ($submit) {
    $filename = '/' . time() . '.mid';

    my $groove = Groovetool->new(
      filename => 'public' . $filename,
      my_bpm   => $my_bpm,
      repeat   => $repeat,
      my_duel  => $my_duel,
      countin  => $countin,
      phrases  => \%phrases,
      dvolume  => $dvolume,
      dreverb  => $dreverb,
      boctave  => $boctave,
      bpatch   => $bpatch,
      bvolume  => $bvolume,
      bnote    => $bnote,
      bscale   => $bscale,
      bsize    => $bsize,
      bpool    => $bpool,
      bweights => $bweights,
      bgroups  => $bgroups,
    );

    $msgs = $groove->process;
  }

  $c->render(
    template => 'index',
    msgs     => $msgs,
    filename => $filename,
    my_bpm   => $my_bpm,
    repeat   => $repeat,
    my_duel  => $my_duel,
    countin  => $countin,
    section  => $section,
    grooves  => \@grooves,
    phrases  => \%phrases,
    kit      => $kit,
    dvolume  => $dvolume,
    dreverb  => $dreverb,
    boctave  => $boctave,
    bpatch   => $bpatch,
    bvolume  => $bvolume,
    bnote    => $bnote,
    bscale   => $bscale,
    bsize    => $bsize,
    bpool    => $bpool,
    bweights => $bweights,
    bgroups  => $bgroups,
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

<form id="groove_form">

<button type="submit" class="btn btn-sm btn-primary" name="generate" value="Generate"><i class="fa fa-cogs" aria-hidden="true"></i> Generate</button>
<button type="button" id="btnAddSection1" class="btnAddSection btn btn-success btn-sm"><i class="fa fa-plus" aria-hidden="true"></i> Add Section</button>

% if ($filename) {
<p></p>
MIDI: &nbsp;
<a href="#" onClick="MIDIjs.play('<%= $filename %>');" title="Play MIDI"><i class="fa-solid fa-play"></i></a>
&nbsp; | &nbsp;
<a href="#" onClick="MIDIjs.stop();" title="Stop MIDI"><i class="fa-solid fa-stop"></i></a>
&nbsp; | &nbsp;
<a href="<%= $filename %>" title="Download MIDI"><i class="fa-solid fa-download"></i></a>
&nbsp;
<%= $filename %>

%   if (@$msgs) {
<p></p>
<ol>
%     for my $msg (@$msgs) {
  <li><%== $msg %></li>
%     }
</ol>
%   }

% }

<p></p>
<div>
Settings:
  <button type="button" class="btn btn-outline-dark btn-sm" data-bs-toggle="collapse" data-bs-target="#generalSettings">General</button>
  <button type="button" class="btn btn-outline-dark btn-sm" data-bs-toggle="collapse" data-bs-target="#drumSettings">Drum</button>
  <button type="button" class="btn btn-outline-dark btn-sm" data-bs-toggle="collapse" data-bs-target="#bassSettings">Bass</button>
</div>

<div class="collapse" id="generalSettings">
  <p></p>
  <div class="d-inline-flex">
    <div class="col-5">
      <select id="loadg" name="loadg" class="form-select form-select-sm" title="Load a saved groove" onchange="this.form.submit()">
        <option value="">Load...</option>
% for my $file (@$grooves) {
        <option value="<%= $file %>"><%= $file %></option>
% }
      </select>
    </div>
    <div class="col-7 px-2">
      <button type="submit" id="saveg" name="saveg" class="btn btn-warning btn-sm" value="<%= $filename %>">Save</button>
      <button type="submit" id="removeg" name="removeg" class="btn btn-warning btn-sm" value="<%= $filename %>">Remove</button>
    </div>
  </div>
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <div class="col-3">
      <label for="my_bpm">BPM</label>
      <input type="number" class="form-control form-control-sm" id="my_bpm" name="my_bpm" min="1" max="200" value="<%= $my_bpm %>" title="1 to 200 beats per minute">
    </div>
    <div class="col-3">
      <label for="repeat">Repeat</label>
      <input type="number" class="form-control form-control-sm" id="repeat" name="repeat" min="1" max="64" value="<%= $repeat %>" title="1 to 64 repeats">
    </div>
  </div>
  <p></p>
  <div class="d-inline-flex align-items-center">
    <div class="form-check form-check-inline">
      <label class="form-check-label" for="countin">Count-in</label>
      <input class="form-check-input" type="checkbox" id="countin" name="countin" <%= $countin ? 'checked' : '' %> title="Play 4 hihat notes to start things off">
    </div>
    <div class="form-check form-check-inline">
      <label class="form-check-label" for="my_duel">Duel</label>
      <input class="form-check-input" type="checkbox" id="my_duel" name="my_duel" <%= $my_duel ? 'checked' : '' %> title="alternate with a hihat-only, 'counterpart' section">
    </div>
  </div>
</div>

<div class="collapse" id="drumSettings">
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <div class="col-3">
      <label for="dvolume">Volume</label>
      <input type="number" class="form-control form-control-sm" id="dvolume" name="dvolume" min="0" max="127" value="<%= $dvolume %>" title="0 to 127 defining the drums volume">
    </div>
    <div class="col-3">
      <label for="dreverb">Reverb</label>
      <input type="number" class="form-control form-control-sm" id="dreverb" name="dreverb" min="0" max="127" value="<%= $dreverb %>" title="0 to 127 drum reverb amount">
    </div>
  </div>
</div>

<div class="collapse" id="bassSettings">
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <div class="col-2">
      <label for="bnote">Note</label>
      <input type="text" class="form-control form-control-sm" id="bnote" name="bnote" value="<%= $bnote %>" maxlength="2" title="C, C#, Db, D, ... B bass scale starting note">
    </div>
    <div class="col-2">
      <label for="bscale">Scale</label>
      <input type="text" class="form-control form-control-sm" id="bscale" name="bscale" value="<%= $bscale %>" title="bass scale name">
    </div>
    <div class="col-2">
      <label for="bpatch">Patch</label>
      <input type="number" class="form-control form-control-sm" id="bpatch" name="bpatch" min="0" max="127" value="<%= $bpatch %>" title="0 to 127 defining the bass patch">
    </div>
    <div class="col-2">
      <label for="bvolume">Volume</label>
      <input type="number" class="form-control form-control-sm" id="bvolume" name="bvolume" min="0" max="127" value="<%= $bvolume %>" title="0 to 127 defining the bass volume">
    </div>
    <div class="col-2">
      <label for="boctave">Octave</label>
      <input type="number" class="form-control form-control-sm" id="boctave" name="boctave" min="1" max="4" value="<%= $boctave %>" title="Bass octave from 1 to 4">
    </div>
    <div class="col-2">
      <label for="bsize">Phrase</label>
      <input type="number" class="form-control form-control-sm" id="bsize" name="bsize" min="1" max="4" value="<%= $bsize %>" title="Phrase size from 1 to 4 beats">
    </div>
  </div>
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <div class="col-4">
      <label for="bpool">Pool</label>
      <input type="text" class="form-control form-control-sm" id="bpool" name="bpool" value="<%= $bpool %>" title="Required allowed durations: qn = quarter note, en = eighth, etc." placeholder="Required allowed durations">
    </div>
    <div class="col-4">
      <label for="bweights">Weights</label>
      <input type="text" class="form-control form-control-sm" id="bweights" name="bweights" value="<%= $bweights %>" title="Optional weights of durations" placeholder="Optional weights of durations">
    </div>
    <div class="col-4">
      <label for="bgroups">Groups</label>
      <input type="text" class="form-control form-control-sm" id="bgroups" name="bgroups" value="<%= $bgroups %>" title="Optional groupings of durations" placeholder="Optional groupings of durations">
    </div>
  </div>
</div>

<div class="sections">

% for my $top (sort map { $_ =~ /^\d+$/ } keys %$phrases) {

  <div id="section_<%= $top %>" class="section">
    <p></p>
    <button type="button" id="btnRemoveSection_<%= $top %>" class="btnRemoveSection btn btn-danger btn-sm"><i class="fa fa-times" aria-hidden="true"></i> Remove Section</button>
    <button type="button" id="btnAddPart_<%= $top %>" class="btnAddPart btn btn-success btn-sm" data-section="<%= $top %>" data-lastpart="<%= $phrases->{$top}{parts} %>"><i class="fa fa-puzzle-piece" aria-hidden="true"></i> Add Part</button>
    <p></p>
    <div class="form-floating d-inline-flex">
      <div class="col-12">
        <label for="bars_<%= $top %>">Bars</label>
        <input type="number" class="form-control form-control-sm" id="bars_<%= $top %>" name="bars_<%= $top %>" min="1" max="32" value="<%= $phrases->{$top}{bars} %>" title="1 to 32 measures">
      </div>
    </div>
    <p></p>
    <div class="form-floating d-inline-flex">
      <div class="col-12">
        <div class="form-check form-check-inline">
          <label class="form-check-label" for="fillin_<%= $top %>">Add Fill</label>
          <input class="form-check-input" type="checkbox" id="fillin_<%= $top %>" name="fillin_<%= $top %>" <%= $phrases->{$top}{fillin} ? 'checked' : '' %> title="Play a fill on the last bar">
        </div>
      </div>
    </div>

    <div id="parts_<%= $top %>" class="parts">

%   for my $key (sort grep { $_ =~ /^$top\_\d+$/ } keys %$phrases) {
%     my $part = $phrases->{$key};

      <div id="part_<%= $key %>" class="part">
        <hr>
        <div class="form-floating d-inline-flex align-items-center">
          <div class="col-7">
            <label for="strike_<%= $key %>">Strike</label>
            <select id="strike_<%= $key %>" name="strike_<%= $key %>" class="form-select form-select-sm" aria-label="Drum strike">
  %     for my $perc (sort keys %$kit) {
              <option value="<%= $kit->{$perc} %>" <%= $part->{strike} == $kit->{$perc} ? 'selected' : '' %>><%= $perc %></option>
  %     }
            </select>
          </div>
&nbsp;
          <div class="col-5">
            <label for="shift_<%= $key %>">Shift by</label>
            <input type="number" class="form-control form-control-sm" id="shift_<%= $key %>" name="shift_<%= $key %>" min="0" max="15" value="<%= $part->{shift} %>" title="Shift sequence by N">
          </div>
        </div>
        <p></p>
        <div class="d-inline-flex">
          <label class="px-1" for="quarter_style_<%= $key %>">Quarter</label>
          <input class="trigger form-check-input" type="radio" name="style_<%= $key %>" id="quarter_style_<%= $key %>" value="quarter" title="Simple quarter note" <%= $part->{style} eq 'quarter' ? 'checked' : '' %>>
        </div>
        <div class="d-inline-flex">
          <label class="px-1" for="eighth_style_<%= $key %>">Eighth</label>
          <input class="trigger form-check-input" type="radio" name="style_<%= $key %>" id="eighth_style_<%= $key %>" value="eighth" title="Simple eighth notes" <%= $part->{style} eq 'eighth' ? 'checked' : '' %>>
        </div>
        <div class="d-inline-flex">
          <label class="px-1" for="euclid_style_<%= $key %>">Euclid</label>
          <input class="trigger form-check-input" type="radio" name="style_<%= $key %>" id="euclid_style_<%= $key %>" value="euclid" title="Euclidean word" <%= $part->{style} eq 'euclid' ? 'checked' : '' %>>
        </div>
        <div class="d-inline-flex">
          <label class="px-1" for="christo_style_<%= $key %>">Christoffel</label>
          <input class="trigger form-check-input" type="radio" name="style_<%= $key %>" id="christo_style_<%= $key %>" value="christoffel" title="Christoffel word" <%= $part->{style} eq 'christoffel' ? 'checked' : '' %>>
        </div>
        <div id="euclidwidgets_<%= $key %>" class="euclid toggle">
          <p></p>
          <div class="form-floating d-inline-flex align-items-center">
            <div class="col-12">
              <label for="onsets_<%= $key %>">Euclidean onsets</label>
              <input type="number" class="form-control form-control-sm" id="onsets_<%= $key %>" name="onsets_<%= $key %>" min="1" max="16" value="<%= $part->{onsets} %>" title="Number of Euclidean onsets">
            </div>
          </div>
        </div>
        <div id="christoffelwidgets_<%= $key %>" class="christoffel toggle">
          <p></p>
          <div class="form-floating d-inline-flex align-items-center">
            <div class="col-4">
              <label for="numerator_<%= $key %>">Numerator</label>
              <input type="number" class="form-control form-control-sm" id="numerator_<%= $key %>" name="numerator_<%= $key %>" min="1" max="16" value="<%= $part->{numerator} %>" title="Christoffel numerator">
            </div>
&nbsp;
            <div class="col-4">
              <label for="denominator_<%= $key %>">Denominator</label>
              <input type="number" class="form-control form-control-sm" id="denominator_<%= $key %>" name="denominator_<%= $key %>" min="1" max="16" value="<%= $part->{denominator} %>" title="Christoffel denominator">
            </div>
&nbsp;
            <div class="col-4">
              <label for="case_<%= $key %>">Case</label>
              <select id="case_<%= $key %>" name="case_<%= $key %>" class="form-select form-select-sm" aria-label="Upper or lower word" title="Upper or lower Christoffel word">
                <option value="u" <%= $part->{case} && $part->{case} eq 'u' ? 'selected' : '' %>>Upper</option>
                <option value="l" <%= $part->{case} && $part->{case} eq 'l' ? 'selected' : '' %>>Lower</option>
              </select>
            </div>
          </div>
        </div>
%       if ($part->{pattern}) {
%         my $j = 0;
        <input type="hidden" name="pattern_<%= $key %>" id="pattern_<%= $key %>" value="<%= $part->{pattern} %>">
        <p></p>
        <div class="form-floating d-inline-flex align-items-center">
%         for my $bit (split //, $part->{pattern}) {
%           $j++;
          <input class="form-check-input" type="checkbox" name="bit_<%= $key %>_<%= $j %>" id="bit_<%= $key %>_<%= $j %>" value="1" title="Beat bit # <%= $j %>" <%= $bit ? 'checked' : '' %> disabled>
%         }
        </div>
%       }
        <p></p>
        <button type="button" id="btnRemove_<%= $key %>" class="btnRemovePart btn btn-secondary btn-sm"><i class="fa fa-trash" aria-hidden="true"></i> Remove Part</button>
      </div> <!-- part -->

%   }

    </div> <!-- parts -->

  </div> <!-- section -->

% }

</div> <!-- sections -->

<div class="defaultSection d-none">
  <p></p>
  <button type="button" id="btnRemoveSection" class="btnRemoveSection btn btn-danger btn-sm"><i class="fa fa-times" aria-hidden="true"></i> Remove Section</button>
  <button type="button" id="btnAddPart" class="btnAddPart btn btn-success btn-sm" data-section="0" data-lastpart="0"><i class="fa fa-puzzle-piece" aria-hidden="true"></i> Add Part</button>
  <p></p>
  <div class="form-floating d-inline-flex">
    <div class="col-12">
      <label for="bars">Bars</label>
      <input type="number" class="form-control form-control-sm" id="bars" name="bars" min="1" max="32" value="4" title="1 to 32 measures">
    </div>
  </div>
  <p></p>
  <div class="form-floating d-inline-flex">
    <div class="col-12">
      <div class="form-check form-check-inline">
        <label class="form-check-label" for="fillin">Add Fill</label>
        <input class="form-check-input" type="checkbox" id="fillin" name="fillin" title="Play a fill on the last bar">
      </div>
    </div>
  </div>
</div>

<div class="defaultPart d-none">
  <hr>
  <p></p>
  <div class="form-floating d-inline-flex align-items-center">
    <div class="col-7">
      <label for="strike">Strike</label>
      <select id="strike" name="strike" class="form-select form-select-sm" aria-label="Drum strike">
% for my $perc (sort keys %$kit) {
        <option value="<%= $kit->{$perc} %>"><%= $perc %></option>
% }
      </select>
    </div>
&nbsp;
    <div class="col-5">
      <label for="shift">Shift by</label>
      <input type="number" class="form-control form-control-sm" id="shift" name="shift" min="0" max="15" value="" title="Shift sequence by N">
    </div>
  </div>
  <p></p>
  <div class="d-inline-flex">
    <label class="px-1" for="quarter_style">Quarter</label>
    <input class="trigger form-check-input" type="radio" name="style" id="quarter_style" value="quarter" title="Simple quarter note">
  </div>
  <div class="d-inline-flex">
    <label class="px-1" for="eighth_style">Eighth</label>
    <input class="trigger form-check-input" type="radio" name="style" id="eighth_style" value="eighth" title="Simple eighth notes">
  </div>
  <div class="d-inline-flex">
    <label class="px-1" for="euclid_style">Euclid</label>
    <input class="trigger form-check-input" type="radio" name="style" id="euclid_style" value="euclid" title="Euclidean word">
  </div>
  <div class="d-inline-flex">
    <label class="px-1" for="christo_style">Christoffel</label>
    <input class="trigger form-check-input" type="radio" name="style" id="christo_style" value="christoffel" title="Christoffel word">
  </div>
  <div id="euclidwidgets" class="euclid toggle">
    <p></p>
    <div class="form-floating d-inline-flex align-items-center">
      <div class="col-12">
        <label for="onsets">Euclidean onsets</label>
        <input type="number" class="form-control form-control-sm" id="onsets" name="onsets" min="1" max="16" value="" title="Number of Euclidean onsets">
      </div>
    </div>
  </div>
  <div id="christoffelwidgets" class="christoffel toggle">
    <p></p>
    <div class="form-floating d-inline-flex align-items-center">
      <div class="col-4">
        <label for="numerator">Numerator</label>
        <input type="number" class="form-control form-control-sm" id="numerator" name="numerator" min="1" max="16" value="" title="Christoffel numerator">
      </div>
&nbsp;
      <div class="col-4">
        <label for="denominator">Denominator</label>
        <input type="number" class="form-control form-control-sm" id="denominator" name="denominator" min="1" max="16" value="" title="Christoffel denominator">
      </div>
&nbsp;
      <div class="col-4">
        <label for="case">Case</label>
        <select id="case" name="case" class="form-select form-select-sm" aria-label="Upper or lower word" title="Upper or lower Christoffel word">
          <option value="u">Upper</option>
          <option value="l">Lower</option>
        </select>
      </div>
    </div>
  </div>
  <p></p>
  <button type="button" id="btnRemove" class="btnRemovePart btn btn-secondary btn-sm"><i class="fa fa-trash" aria-hidden="true"></i> Remove Part</button>
</div>

<p></p>
<button type="submit" class="btn btn-sm btn-primary" name="generate" value="Generate"><i class="fa fa-cogs" aria-hidden="true"></i> Generate</button>
<button type="button" id="btnAddSection2" class="btnAddSection btn btn-success btn-sm"><i class="fa fa-plus" aria-hidden="true"></i> Add Section</button>

</form>

<script>
$(document).ready(function () {
  var i = <%= $section || 0 %>; // section counter
  $(".btnAddSection").click(function () {
    i++;
    var $appendItem = $(".defaultSection").html();
    $("<div />", { "class":"section", id:"section_" + i }).append(
      $($appendItem)).appendTo(".sections");
    $("<div />", { "class":"parts", id:"parts_" + i })
      .appendTo("#section_" + i);
    var $inputs = $("#section_" + i).find(":input");
    $inputs.each(function (index) {
      $(this).attr("id", $(this).attr("id") + "_" + i);
      $(this).attr("name", $(this).attr("name") + "_" + i);
      $(this).prevAll("label:first").attr("for", $(this).attr("id"));
    });
    $("#btnAddPart_" + i).attr("data-section", i);
  });
  $("body").on("click", ".btnRemoveSection", function() {
    var result = confirm("Remove this section?");
    if (result) $(this).closest(".section").remove();
  });
  $("body").on("click", ".btnAddPart", function () {
    var section = $(this).attr("data-section");
    var j = parseInt($("#btnAddPart_" + section).attr("data-lastpart"));
    j++;
    var $appendItem = $(".defaultPart").html();
    $("<div />", { "class":"part", id:"part_" + section + "_" + j }).append(
      $($appendItem)).appendTo("#parts_" + section);
    var $inputs = $("#part_" + section + "_" + j).find(":input");
    $inputs.each(function (index) {
      $(this).attr("id", $(this).attr("id") + "_" + section + "_" + j);
      $(this).attr("name", $(this).attr("name") + "_" + section + "_" + j);
      $(this).prevAll("label:first").attr("for", $(this).attr("id"));
    });
    var $divs = $("#part_" + section + "_" + j).find("div");
    $divs.each(function (index) {
      if ($(this).attr("id"))
        $(this).attr("id", $(this).attr("id") + "_" + section + "_" + j);
    });
    $("#btnAddPart_" + section).attr("data-lastpart", j);
  });
  $("body").on("click", ".btnRemovePart", function() {
    var result = confirm("Remove this part?");
    if (result) {
      $(this).closest(".part").remove();
    }
  });
  $("body").on("click", "#removeg", function() {
    var result = confirm("Remove this groove?");
    if (result) {
      return true;
    }
    return false;
  });
  $("body").on("click", ".trigger", function() {
    var name = $(this).val();
    var id = $(this).attr("id");
    var num = id.substring(id.length - 4);
    $("div[class~=toggle][id$=" + num + "]").hide().filter("." + name).show()
    // TODO .focus()
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
      body {
        background-image: url("/bg.jpg");
        background-position: center;
        background-repeat: no-repeat;
        background-attachment: fixed;
        background-size: cover;
        -webkit-background-size: cover;
        -moz-background-size: cover;
        -o-background-size: cover;
      }
      a:link, a:visited, a:hover, a:active, a:focus {
        color: #414A4C;
        text-decoration: none;
      }
      .toggle {
        display: none
      }
      .padpage {
        padding-top: 10px;
        padding-bottom: 10px;
      }
      .faded {
        opacity: 0.95;
        background-color: lightgray;
      }
      .smalltext {
        font-size: small;
        color: black;
      }
    </style>
  </head>
  <body>
    <p></p>
    <div class="container padpage faded">
      <h3><a href="/"><%= title %></a></h3>
      <%= content %>
      <p></p>
      <div id="footer" class="smalltext">
        <hr>
        Built by <a href="http://gene.ology.net/">Gene</a>
        with <a href="https://www.perl.org/">Perl</a> and
        <a href="https://mojolicious.org/">Mojolicious</a>
        | <a href="/help">Help!</a>
      </div>
    </div>
  </body>
</html>
