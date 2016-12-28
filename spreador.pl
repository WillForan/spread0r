#!/usr/bin/perl
#
# Mod. 2016 Will Foran
#
# Copyright (C) 2014 Peter Feuerer <peter@piie.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


use strict;
use utf8;
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Getopt::Long;
use Pod::Usage;
use feature 'say';

use experimental qw(switch signatures);
#use feature qw(switch);
use Gtk2::Gdk::Keysyms;

# defines

my $VERBOSE=1;


# SETTINGS
our $wpm = 340;
my $word_width = 28;
my $font = "Helvetica 24";
my $bg_color = "black";
my $fg_color = "grey";
my $hl_color = "red";
my $browser = "firefox";

my $span_bg_open = "<span background='$bg_color' foreground='$fg_color' font_desc='".$font."'><big>";
my $span_fg_open  = "<span background='$bg_color' foreground='$hl_color'  font_desc='".$font."'><big>";
my $span_close = "</big></span>";
my $spread0r_version = "2.0";

# globaly used gtk stuff

our $gtk_text;
our $window;
our $gtk_timer;
our $pause = 0;




####################
# Helper functions #
####################



sub escape {
	my($data) = @_;

	$data =~ s/&/&amp;/sg;
	$data =~ s/</&lt;/sg;
	$data =~ s/>/&gt;/sg;
	$data =~ s/"/&quot;/sg;

	return $data;
}

# use lib 'lib/';
# use Hyphen;
# my $hyphen = Text::Hyphen->new('min_word' => 15,
# 	'min_prefix' => 7, 'min_suffix' => 7, 'min_part' => 6);
# my @words_buffer;
# sub limit_word_length
# {
# 	my $i = 0;
# 	for ($i = 0; $i <= $#words_buffer; ++$i) {
# 		my @tmp_buffer = ();
# 		@tmp_buffer = $hyphen->hyphenate($words_buffer[$i]);
# 		# if hyphenate happened, replace original word by hyphen array
# 		if ($#tmp_buffer > 0) {
# 			$tmp_buffer[$_] .= "-" foreach (0 .. $#tmp_buffer - 1);
# 			splice(@words_buffer, $i, 1, @tmp_buffer);
# 		}
# 	}
# }
# 

#################
# GTK callbacks #
#################



sub lookup_word($word) {
 system("$browser 'define: $word'"); 
}

sub open_at {
 button_pause();
 1;
}


######################
# GTK timer callback #
######################



sub keyin {
  my $key=shift;
  my $in=grep($key==$_,@Gtk2::Gdk::Keysyms{@_});
  return $in>0 
}

#### REIMPLEMENT

sub word_into_buf($word,$buf) {

 # build buffer 
 my $displen=3;
 # make empty if wrong size 
 # this should only happen on initialization
 @$buf = ("*") x $displen if $displen > $#$buf+1;
 @$buf = ( @$buf[1..($displen-1)], $word );
 
}

sub calc_timeout($word,$wpm) {
	my $timeout = 60000 / $wpm;
	my $next_shot = $timeout;
	my $word_length = length($word);
   
	# calculate timeout for next run
	$next_shot += ($timeout / 5 ) * ($word_length - 6) if ($word_length > 6);
	$next_shot += $timeout / 2 if ($word =~ /.*,$/);
	$next_shot += $timeout * 1.5 if ($word =~ /.*[\.!\?;]«?$/);
   return($next_shot);
}

sub set_timer($wait,$func) {
   our $pause;
   our $gtk_timer;
	Glib::Source->remove($gtk_timer);
	if (!$pause) {
		$gtk_timer = Glib::Timeout->add($wait,$func);
	}
   return TRUE;
}

# return an xml encoded, vowel centered and colored, word
sub vowel_centered_word_split($word,$word_width) {
   # SETTING: how big is the word display
   #my $word_width = 28;

	my $word_length = length($word);

   # find the position of the first vowel before the halfway point
   # if none, pick the halfway point
   my $half_pnt = $word_length/2;
   my ($first_novowel,@rest_novowel) = split( /[aeuioöäü]+/i, $word);
   my $focus_pnt = length($first_novowel);
   $focus_pnt = $half_pnt if $focus_pnt > $half_pnt;
   
   # parts of the word
   my @parts = (
      substr($word,0,$focus_pnt),
      substr($word,$focus_pnt,1),
      substr($word,$focus_pnt+1)
   );

   # pad the front and back to make sure the word evenly fills
   # the word_width space allocated to each word
   my $in_front  = $word_width/2 - length($parts[0]);
   my $in_back   = $word_width/2 - length($parts[2]);
   $parts[0]  = " "x$in_front . $parts[0] if $in_front>0;
   $parts[2] .= " "x$in_back if $in_back>0;
   return(@parts);
}

sub pretty_vowel_join(@parts){
   # escape spaces and other xml characters
   @parts = map {escape($_)} @parts;
   

   # TODO: rename black and blue to bg fg
   # nest xml instead of open close
	my $word = join("",
            $span_bg_open, $parts[0], $span_close,
            $span_fg_open,  $parts[1], $span_close,
            $span_bg_open, $parts[2], $span_close);

   return($word);
}
# return the word centered
sub center_word($word,$word_width) {
   my $word_length = length($word);

   # truncate word if its too long
   if($word_length > $word_width) {
     $word=substr($word,0,$word_width-3)."..."; 
     return($word)
   }

   # pad the word such that it is centered
   # but more white space on the back than front if uneven
   my $offset=$word_width - $word_length;
   $word = " "x int($offset/2     ) . $word;
   $word.= " "x int($offset/2 +.5 );
   return($word);

}

sub show_words($buf){
  my $word = $buf->[$#$buf];
  my $markup =  pretty_vowel_join(vowel_centered_word_split($word,$word_width));
  $gtk_text->set_markup($markup);
}

sub cnt_title($cnt) {
  my $title="$cnt->{byte} / $cnt->{bytes_total} ($cnt->{line})";
  settitle($title);
}

sub gtk_show($word,$buf,$cnt) {
 our $wpm;
 my $waittime=calc_timeout($word,$wpm);
 say "showing $word with $waittime" if $VERBOSE;
 set_timer($waittime, sub { show_words($buf); cnt_title($cnt) });
}
sub stall(){
 while($pause){

 }
}

# get the next word into buffer
# set count metrics
# return the word
sub next_words($FH,$buf,$cnt) {
 # make the record separator a space. 
 # we'll need to capture other \s;
 local $/=' ';
 my $record = <$FH>;

 # where are we in the file
 # is not accurate to the word.
 # same count for both words in word1\nword2 
 $cnt{byte} = tell($FH); 
 
 # skip if nothing but weird white characters
 if( $record =~ m/^\s+$/){
   return next_word($FH,$buf,$cnt);
 }

 # most of the time, should be 1 element array
 my @words=split(/\s+/,$record); 
 for my $word (@words){
   $cnt{word}++;
   word_into_buf($word,$buf);
   gtk_show($word,$buf,$cnt);
   stall();
 }
 
 # line count will likely be off for the word before the \n
 # b/c we are reading in like word1\nword2
 $cnt{line}++ if $record =~ m/\n/;

}

sub main2 {

   our $wpm;
   our $window;

   my $file = '/home/foranw/Downloads/Infomacracy_book/i.txt';
   my $FH;
   my %cnt={byte=>0, line=>0, word=>0,bytes_total=>0};
   my @buf=();
   

   ####
   # gui
	# show window and start gtk main
   $window = setup_gtk();
	$window->show_all;
	Gtk2->main;


   ####
   
   # TODO dont ask this of a pipe
   $cnt{bytes_total}= -s $file;

	open( $FH, "<:encoding(UTF-8)", $file) || die "can't open UTF-8 encoded filename: $!";

   next_word($FH);

   close($FH);
}

sub quitcall(){
	Gtk2->main_quit;
   return TRUE;
}
sub settitle($text){
   our $window;
   say "setting title: '$text'" if $VERBOSE;
   $window->set_title("spread0r.pl: [@ $wpm] $text ") if $window;
}

# setup gtk interface
sub setup_gtk() {
	# set up window and quit callbacks
	our $window = Gtk2::Window->new;
   $window->modify_bg('normal',Gtk2::Gdk::Color->parse($bg_color));
   settitle('');
	$window->signal_connect(delete_event => \&quitcall);
	$window->signal_connect(destroy      =>  \&quitcall);
	$window->set_border_width(10);


	# text label, showing the actual word
   #$word=" "x$word_width;
   my $word="Push spacebar to start reading";
	$gtk_text = Gtk2::Label->new($word);
	$gtk_text->set_markup($span_bg_open.$word.$span_close);
	

   my $color = Gtk2::Gdk::Color->parse($bg_color);
   $window->modify_bg('normal', $color);

   my $vbox = Gtk2::VBox->new(FALSE, 10);
   $vbox->pack_start($gtk_text, TRUE, TRUE, 5);
	$window->add($vbox);

   # bind keyboard events
   $window->signal_connect('key-press-event' => \&keycall, $window);


   return($window)
}

sub toggle_pause(){
 our $pause;
 our $gtk_timer;
 if ($pause) {
 	$gtk_timer = Glib::Timeout->add(500, sub{1;});
 	$pause = 0;
 } else {
 	$pause = 1;
 	Glib::Source->remove($gtk_timer);
 }
 return TRUE;
}

sub keycall {
 my ($widget,$event,$window) = @_;
 my $key = $event->keyval();

 given($key) {
   when($Gtk2::Gdk::Keysyms{space} ) { toggle_pause();}

   when(keyin($key,qw/Escape q/)) { quitcall() ;}
   #when(keyin($key,qw/< b   h leftarrow/)) { button_back; set_text;}
   #when(keyin($key,qw/>     l rightarrow/)) { button_forward; set_text;}
   when(keyin($key,qw/minus  k downarrow/)) { adjust_wpm(-10); settitle('');}
   when(keyin($key,qw/plus j uparrow/)) { adjust_wpm(+10); settitle('');}


   when($Gtk2::Gdk::Keysyms{o} ) { open_at;}
   when($Gtk2::Gdk::Keysyms{d} ) { lookup_word;}
	

   default {}
 }
}

sub adjust_wpm($inc) {
 our $wpm;
 my $maxwpm=500; my $minwpm=50;
 $wpm += $inc;
 $wpm=$maxwpm if($wpm>$maxwpm);
 $wpm=$minwpm if($wpm<$minwpm);
 say "new wpm = $wpm";
}


main2();




################
# help and man #
################

__END__

=head1 NAME

spread0r - high performance txt reader

=head1 SYNOPSIS

spread0r [options] file

	Options:
	-h, --help			print brief help message
	-v, --version			print version and quit
	-m, --man			print the full documentation
	-u, --ui			full ui
	-w <num>, --wpm <num>		reading speed in words per minute
	-f <num>, --fastforward <num>	seek to <num>. sentence


=head1 OPTIONS

=over 8

=item B<-h, --help>

Print a brief help message and exits.

=item B<-v, --version>

Print version and exits.

=item B<-m, --man>

print the full documentation

=item B<-u, --ui>
open with menu and buttons

=item B<-w, --wpm>

Set the reading speed to the given amount of words per minute.
For beginners a good starting rate is around 250

=item B<-f, --fastforward>

Skip all sentences until it reaches given sentence

=back

=head1 DESCRIPTION

B<spread0r> will read the given utf8 encoded input file and present
it to you word by word, so you can read the text without manually
refocusing.  This can double your reading speed!

=head2 Keys

=over 8

=item B<Escape, q>

 quit

=item B<h, E<lt>, b, leftarrow>

 move back

=item B<l, E<gt>, rightarrow>

 move foward

=item B<-, j, downarrow>

 slower

=item B<+, k, uparrow>

 faster

=item B<d>

 launch browser to define current word

=item B<o>

 TODO: open in text editor at position

=back


=cut
