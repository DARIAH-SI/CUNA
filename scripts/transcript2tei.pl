#!/usr/bin/env perl

use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
binmode STDERR, 'utf8';
binmode STDIN,  'utf8';
binmode STDOUT, 'utf8';
use Getopt::Long;
use XML::LibXML;
use XML::LibXML::PrettyPrint;
use Text::CSV qw/csv/;
use File::Basename;
use File::Path;
use File::Spec;
use Data::Dumper;

my $id;
my $in_file;
my $out_file;

GetOptions (
    'id=s' => \$id,
    'in=s' => \$in_file,
    'out=s' => \$out_file,
  );


my $tsv = Text::CSV->new({
        binary => 1,
        auto_diag => 1,
        sep_char=> "\t",
        quote_char => undef,
        escape_char => undef
      });

open my $IN, "<:encoding(utf8)", $in_file  or die "$in_file: $!";
$tsv->column_names(qw/start end text/);

my $interview = init_interview($id);

my %state_global = map {$_ => undef} qw/speaker language topic text_beep/;
$state_global{language} = 'uk';
$state_global{text_beep} = 'text';

my ($u,$seg);
my $u_cnt = 0;
my $seg_cnt = 0;
$interview->{timeline}->{cnt} = 0;

while(my $row = $tsv->getline_hr($IN)){
  print STDERR "LINE: ".$row->{text}."\n";
  next if $row->{text} =~ m/^\s*$/;
  my ($changed_speaker, $changed_topic) = (0, 0); 
  if( $row->{text} =~ s/^\s*\<([^\>]*)\>\s*//){ # update global state
    my %state_update = parse_setting($1);
    # initialize new utterance if speaker changed
    $changed_speaker = is_change($state_global{speaker}, $state_update{speaker});
    # initialize new segment if topic changed
    $changed_topic = is_change($state_global{topic}, $state_update{topic});
    print STDERR "ERROR: unexpected global language change - ignoring\n" if is_change($state_global{language}, $state_update{language});
    print STDERR "ERROR: unexpected global text_beep change - ignoring\n" if is_change($state_global{text_beep}, $state_update{text_beep});
    %state_global = (%state_global,%state_update);
  }
  if($changed_speaker){ # set new speech
    print STDERR "\tnew speech: ".$state_global{speaker}."\n";
    $u_cnt += 1;
    $seg_cnt = 0;
    $u = $interview->{div}->addNewChild(undef,'u');
    $u->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',compute_id($id,$u_cnt));
    $u->setAttribute('ana',$state_global{speaker} eq 'host' ? '#interviewer' : '#interviewee');

  }
  if($changed_topic || $changed_speaker){ # set new paragraph
    print STDERR "\t\tnew seg: ".$state_global{topic}."\n";
    $seg_cnt += 1;
    $interview->{timeline}->{cnt} = 0;
    $seg = $u->addNewChild(undef,'seg');
    $seg->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',compute_id($id,$u_cnt,$seg_cnt));
    $seg->setAttribute('ana',join(" ",map {"#$_"} split(/ /,$state_global{topic})));
  }
  my %state_local = %state_global;
  # process the row:
  # set anchor at the beginning
  add_anchor($seg, $interview->{timeline}, 'start', $row->{start});

  #place local changes in <span> for language, <del> for censoring
  my $elem = $seg;
  while($row->{text}){
    if($row->{text} =~ s/^\[([^\]]*)\]//) {
      my %state_update = parse_setting($1);
      print STDERR "INFO: local_ana='$1'\n";
      print STDERR "ERROR: unexpected local speaker change - ignoring\n" if is_change($state_local{speaker}, $state_update{speaker});
      print STDERR "ERROR: unexpected local topic change - ignoring\n" if is_change($state_local{topic}, $state_update{topic});
      my $changed_lang = is_change($state_local{language}, $state_update{language});
      my $changed_text_beep = is_change($state_local{text_beep}, $state_update{text_beep});
      print STDERR "ERROR: unexpected local change - both language and text_beep\n" if $changed_lang && $changed_text_beep;
      if($changed_text_beep){
        if($state_update{text_beep} eq 'text') {
          $elem = $seg;
        } else {
          $elem = $seg->addNewChild(undef,'del');
        }
      }
      if($changed_lang){
        if($state_update{language} eq $state_global{language}) {
          $elem = $seg;
        } else {
          $elem = $seg->addNewChild(undef,'span');
          $elem->setAttributeNS('http://www.w3.org/XML/1998/namespace','lang',$state_update{language});
        }
      }
      %state_local = (%state_local,%state_update);
      print STDERR to_string($elem),"\n";
    } elsif ($row->{text} =~ s/([^\[]*)//) {
      $elem->appendText($1);
      print STDERR "INFO: text='$1'\n";
    }
  }
  #$seg->appendText($row->{text});

  # set anchor at the end
  add_anchor($seg, $interview->{timeline}, 'end', $row->{end});
  

  print STDERR Dumper(\%state_local);


}


save_xml($interview->{tei}, $out_file);
close $IN;

sub add_anchor {
  my ($seg, $timeline, $type, $time_ms) = @_;
  $seg->appendText(' ') if $timeline->{cnt} > 0 && $type eq 'start';
  $timeline->{cnt} += 1;
  my $id = $seg->getAttributeNS('http://www.w3.org/XML/1998/namespace','id').'.when'.$timeline->{cnt};
  my $anchor = $seg->addNewChild(undef,'anchor');
  $anchor->setAttribute('synch',"#$id");
  $anchor->setAttribute('type',$type);
  my $when = $timeline->{tl}->addNewChild(undef,'when');
  $when->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',$id);
  $when->setAttribute('since', "#".$timeline->{origin});
  $when->setAttribute('interval', $time_ms);
}

sub is_change { 
  my ($old, $new) = @_;
  return 1 unless $old; # not necesarily change, but it forces to create a new element
  return 0 unless $new;
  return $old ne $new;
}

sub compute_id {
  my $id = shift;
  if(my $c = shift){
    $id .= ".u$c";
  }
  if(my $c = shift){
    $id .= ".p$c";
  }
  return $id;
}
sub parse_setting {
  my @setting = split(/  */, shift);
  my %state_update;## = map {$_ => undef} qw/speaker language topic text_beep/;
  while(my $s = shift @setting){
    if($s =~ m/topic/){
      $state_update{topic}=[] unless exists $state_update{topic};
      push(@{$state_update{topic}}, $s);
    } elsif($s =~ m/text|beep/){
      $state_update{text_beep} = $s
    } elsif($s =~ m/host|guest/){
      $state_update{speaker} = $s
    } else {
      $state_update{language} = $s
    }
  }
  $state_update{topic} = join(' ',sort @{$state_update{topic}}) if exists $state_update{topic};
  return %state_update;
}

sub init_interview {
  my ($id) = @_;
  my $tei = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node = XML::LibXML::Element->new('TEI');
  $tei->setDocumentElement($root_node);

  $root_node->setNamespace('http://www.tei-c.org/ns/1.0','',1);
  $root_node->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',$id);
  $root_node->setAttributeNS('http://www.w3.org/XML/1998/namespace','lang','uk');
 
  my $parser = XML::LibXML->new();
  my $teiHeader = $parser->parse_balanced_chunk(
<<HEADER
<teiHeader>
  <fileDesc>
         <titleStmt>
            <!-- TODO -->
         </titleStmt>
         <editionStmt>
            <!-- TODO -->
         </editionStmt>
         <extent>
           <!-- TODO -->
         </extent>
         <publicationStmt>
            <!-- TODO -->
         </publicationStmt>
         <sourceDesc>
            <bibl>
               <!-- TODO -->
            </bibl>
            <recordingStmt>
               <recording type="audio">
                  <media xml:id="$id.audio"
                         mimeType="audio/wav"
                         url="audio/$id.wav"/>
               </recording>
            </recordingStmt>
         </sourceDesc>
      </fileDesc>
      <encodingDesc>
         <!-- TODO -->
      </encodingDesc>
      <profileDesc>
         <settingDesc>
            <setting>
               <!-- TODO -->
            </setting>
         </settingDesc>
         <!-- TODO -->
      </profileDesc>
   </teiHeader>
HEADER
    );
  $root_node->appendChild($teiHeader);
  my $body = $root_node->addNewChild(undef,'text')->addNewChild(undef,'body');
  my $div = $body->addNewChild(undef,'div');
  my $timeline = $body->addNewChild(undef,'timeline');
  my $id_origin = "$id.audio.origin";
  $timeline->setAttribute('corresp',"#$id.audio");
  $timeline->setAttribute('unit','ms');
  $timeline->setAttribute('origin',"#$id_origin");
  my $origin = $timeline->addNewChild(undef,'when');
  $origin->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',$id_origin);
  
  print STDERR "INFO: Processing  ($id)\n";
  return {
    id => $id,
    tei => $tei,
    div => $div,
    timeline => {
      tl => $timeline,
      origin => $id_origin,
    }
  };
}


sub to_string {
  my $doc = shift;
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "   ",
    element => {
        inline   => [qw//], # note
        block    => [qw/person/],
        compact  => [qw/catDesc term label date edition title meeting idno orgName persName resp licence language sex forename surname measure head roleName/],
        preserves_whitespace => [qw/s seg note ref p desc name/],
        }
    );
  $pp->pretty_print($doc);
  return $doc->toString();
}

sub print_xml {
  my $doc = shift;
  binmode STDOUT;
  print to_string($doc);
}

sub save_xml {
  my ($doc,$filename) = @_;
  print STDERR "INFO: Saving to $filename\n";
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;
  open FILE, ">$filename";
  binmode FILE;
  my $raw = to_string($doc);
  print FILE $raw;
  close FILE;
}