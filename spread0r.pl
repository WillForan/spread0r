#!/usr/bin/perl
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
use lib 'lib/';
use Hyphen;

use experimental 'switch';
#use feature qw(switch);
use Gtk2::Gdk::Keysyms;

# defines
my $minimal_ui = 1;
my $browser = "firefox";

my $VERBOSE=1;

my $font = "Helvetica 24";
my $bg_color = "black";
my $fg_color = "grey";
my $hl_color = "red";

my $span_black_open = "<span background='$bg_color' foreground='$fg_color' font_desc='".$font."'><big>";
my $span_blue_open  = "<span background='$bg_color' foreground='$hl_color'  font_desc='".$font."'><big>";
my $span_close = "</big></span>";
my $word_width = 28;
my $spread0r_version = "1.0";

# globaly used gtk stuff
my $gtk_text;
my $gtk_speed_label;
my $gtk_sentence_text;
my $gtk_timer;

# global variables
my $wpm = 340;
my $pause_button;
my $pause = 1;
my $back_ptr = -1;
my $prev_back_ptr = -1;
my $fast_forward = 0;
my $hyphen = Text::Hyphen->new('min_word' => 15,
	'min_prefix' => 7, 'min_suffix' => 7, 'min_part' => 6);


my $current_word="";
my %current_position = (line=>0,word=>0,column=>0,sentence=>0);

####################
# Helper functions #
####################


sub get_line
{
	my $line;
	$/ = '.';

	if (!($line = <FILE>)) {
		printf("reached end of file\n");
		close(FILE);
		exit(-1);
	}
	$line =~ s/[\n\r]/ /g;

   $current_position{line}++;
   $current_position{word}=0;

	return $line;
}

sub escape {
	my($data) = @_;

	$data =~ s/&/&amp;/sg;
	$data =~ s/</&lt;/sg;
	$data =~ s/>/&gt;/sg;
	$data =~ s/"/&quot;/sg;

	return $data;
}

my @words_buffer;
sub limit_word_length
{
	my $i = 0;
	for ($i = 0; $i <= $#words_buffer; ++$i) {
		my @tmp_buffer = ();
		@tmp_buffer = $hyphen->hyphenate($words_buffer[$i]);
		# if hyphenate happened, replace original word by hyphen array
		if ($#tmp_buffer > 0) {
			$tmp_buffer[$_] .= "-" foreach (0 .. $#tmp_buffer - 1);
			splice(@words_buffer, $i, 1, @tmp_buffer);
		}
	}
}

my @back_buffer;
sub get_next_word
{
	my $line;

	@words_buffer = () if ($back_ptr != $prev_back_ptr);
	$back_ptr = -1 if ($back_ptr < -1);
	$prev_back_ptr = $back_ptr;

	$gtk_sentence_text->set_markup("sentence nr: ".($current_position{sentence} - ($back_ptr +1)));

	# if fast foward is specified, search the line
	for (;$fast_forward; $fast_forward--) {
		$line = get_line();
		@words_buffer = split(' ', $line);

		$current_position{sentence}++ if ($#words_buffer >= 0);

		if ($fast_forward < 10) {
			unshift(@back_buffer, $line);
			pop(@back_buffer) if ($#back_buffer > 10);
		}
	}


	# standard operation:
	# check if new word is in @words_buffer otherwise get new line
	# into @words_buffer and insert it in @back_buffer
	if ($back_ptr <= -1) {
		if ($#words_buffer < 0) {
			while ($#words_buffer < 0) {
				$line = get_line();
				@words_buffer = split(' ', $line);
			}
         $current_position{sentence}++;
			#limit_word_length();
			unshift(@back_buffer, $line);
			pop(@back_buffer) if ($#back_buffer > 10);
		}
	} else {
		# somebody is rewinding to previous lines, so put the previous
		# line into @words_buffer
		if ($#words_buffer < 0) {
			@words_buffer = split(' ', $back_buffer[$back_ptr]);
			#limit_word_length();
		}
		# if @words_buffer empty, proceed with next line
		$back_ptr-- if ($#words_buffer <= 0);
	}

   settitle();
	return shift(@words_buffer);
}



#################
# GTK callbacks #
#################

# set gtk window title to include sentence count and wpm
my $window;
sub settitle() {
   $window->set_title("spread0r.pl: $current_position{sentence} @ $wpm ");
}

sub button_quit
{
	Gtk2->main_quit;
	close(FILE);
	return TRUE;
}

sub button_back
{

   print "#going back\n" if $VERBOSE;
	$back_ptr++ if ($back_ptr < 10);
	return TRUE;
}

sub button_forward
{
	$back_ptr-- if ($back_ptr > -2);
   print "#going foward\n" if $VERBOSE;
	return TRUE;
}

sub button_pause 
{
	if ($pause) {
		$gtk_timer = Glib::Timeout->add(500, \&set_text);
		$pause = 0;
		$pause_button->set_label(" || ");
	} else {
		$pause = 1;
		Glib::Source->remove($gtk_timer);
		$pause_button->set_label(" |> ");
	}
	return TRUE;
}

sub button_slower
{
	$wpm -= 10 if ($wpm > 40);
   print "#slower: $wpm\n" if $VERBOSE;
   settitle();
	$gtk_speed_label->set_markup("WPM: $wpm");
	return TRUE;
}

sub button_faster
{
	$wpm += 10 if($wpm < 1000);
   print "#faster: $wpm\n" if $VERBOSE;
   settitle();
	$gtk_speed_label->set_markup("WPM: $wpm");
	return TRUE;
}

sub lookup_word {
 system("$browser 'define: $current_word'"); 
}

sub open_at {
 button_pause();
 1;
}


######################
# GTK timer callback #
######################

sub set_text
{
	my $word = get_next_word();
   $current_word = $word;
	my $timeout = 60000 / $wpm;
	my $next_shot = $timeout;
	my $word_length = length($word);
	my $word_start = "";
	my $word_mid = "";
	my $word_end = "";
	my $prev_vowel = -1;
	my $i = 0;
	my $add_to_end = 0;

	
	# calculate timeout for next run
	$next_shot += ($timeout / 5 ) * ($word_length - 6) if ($word_length > 6);
	$next_shot += $timeout / 2 if ($word =~ /.*,$/);
	$next_shot += $timeout * 1.5 if ($word =~ /.*[\.!\?;]«?$/);

	# search for vowel from start to the mid of the word,
	# this will be the focuspoint of the word
	for ($i = $word_length * 0.2; $i < $word_length / 2; ++$i) {
		if (substr($word, $i, 1) =~ /[aeuioöäü]/i) {
			$prev_vowel = $i;
		}
	}

	# if no vowel was found in the first half of the word,
	# use the letter in the middle as focuspoint
	$prev_vowel = $word_length / 2 if ($prev_vowel == -1);

	# fill the start of the word with spaces, to correctly
	# align it
	for ($i = 0; $i < ($word_width / 2) - $prev_vowel; ++$i) {
		$word_start .= " ";
	}

	$word_start .= escape(substr($word, 0, $prev_vowel));
	$word_mid = escape(substr($word, $prev_vowel , 1));
	$word_end = escape(substr($word, $prev_vowel + 1));
	$add_to_end = $word_width / 2  - length($word_end);

	# fill the string to fit $word_width
	for ($i = 0; $i < $add_to_end ; ++$i) {
		$word_end .= " ";
	}
	$word = $span_black_open.$word_start.$span_close.$span_blue_open.$word_mid.$span_close.$span_black_open.$word_end.$span_close;

	# printf("$word\n");
	$gtk_text->set_markup($word);

	# set new timer / disable in case of pause
	Glib::Source->remove($gtk_timer);
	if (!$pause) {
		$gtk_timer = Glib::Timeout->add($next_shot,\&set_text);
	}
	return TRUE;
}


sub keyin {
  my $key=shift;
  my $in=grep($key==$_,@Gtk2::Gdk::Keysyms{@_});
  return $in>0 
}
sub keyevent {
 my ($widget,$event,$param) = @_;
 my $key = $event->keyval();

 given($key) {
   when($Gtk2::Gdk::Keysyms{space} ) { button_pause;}

   when(keyin($key,qw/Escape q/)) { button_quit ;}
   when(keyin($key,qw/< b   h leftarrow/)) { button_back; set_text;}
   when(keyin($key,qw/>     l rightarrow/)) { button_forward; set_text;}
   when(keyin($key,qw/minus  k downarrow/)) { button_slower;}
   when(keyin($key,qw/plus j uparrow/)) { button_faster;}


   when($Gtk2::Gdk::Keysyms{o} ) { open_at;}
   when($Gtk2::Gdk::Keysyms{d} ) { lookup_word;}
	

   default {}
 }
}

########
# main #
########

sub main
{
	my $quit_button;
	my $back_button;
	my $forward_button;
	my $faster_button;
	my $slower_button;
	my $file_chooser;
	my $vbox;
	my $hbox;
	my $file = "infile.txt";
	my $length = 24;
	my $version = 0;
   my $full_ui = 0;
	my $help = 0;
	my $man = 0;
	my $word = "";
	my $i;

	# handle arguments
	GetOptions (	"wpm|w=i" => \$wpm,
			"fastforward|f=i" => \$fast_forward,
			"version|v" => \$version,
			"help|h" => \$help,
			"ui|u" => \$full_ui,
			"man|m" => \$man)
		or die("Error in command line arguments\n");

	if ($version) {
		printf("$0 version $spread0r_version\n");
		return TRUE;
	}

	pod2usage(1) if ($help);
	pod2usage(-verbose => 2) if ($man);


	# open filechooser in case no file is given via commandline
	if (@ARGV == 0) {
		$file_chooser = Gtk2::FileChooserDialog->new(
			"Open file", undef, "open", 'gtk-cancel' => 'cancel', 'gtk-ok' => 'ok');
		if ($file_chooser->run()) {
			$file = $file_chooser->get_filename();
		}
		$file_chooser->destroy();
	} else {
		$file = $ARGV[0];
	}

	# limit wpm
	$wpm = 40 if ($wpm < 40);
	$wpm = 1000 if ($wpm > 1000);

	# open file
	printf("opening file: $file\n");
	open(FILE, "<:encoding(UTF-8)", $file) || die "can't open UTF-8 encoded filename: $!";

	printf("using words per minute = $wpm\n");

	
	# set up window and quit callbacks
	$window = Gtk2::Window->new;
   $window->modify_bg('normal',Gtk2::Gdk::Color->parse($bg_color));
   settitle();
	$window->signal_connect(delete_event => \&button_quit);
	$window->signal_connect(destroy =>  \&button_quit);
	$window->set_border_width(10);

	# quit button
	$quit_button = Gtk2::Button->new("Quit");
	$quit_button->signal_connect(clicked => \&button_quit, $window);

	# # backward button
	$back_button = Gtk2::Button->new(" << ");
	$back_button->signal_connect(clicked => \&button_back, $window);

	# forward button
	$forward_button = Gtk2::Button->new(" >> ");
	$forward_button->signal_connect(clicked => \&button_forward, $window);

	# pause button
	$pause_button = Gtk2::Button->new(" |> ");
	$pause_button->signal_connect(clicked => \&button_pause, $window);

	# faster button
	$faster_button = Gtk2::Button->new(" + ");
	$faster_button->signal_connect(clicked => \&button_faster, $window);

	# slower button
	$slower_button = Gtk2::Button->new(" - ");
	$slower_button->signal_connect(clicked => \&button_slower, $window);

	# text label, showing the actual speed
	$gtk_speed_label = Gtk2::Label->new();
	$gtk_speed_label->set_markup("WPM: $wpm");

	# text label, showing the actual word
   #$word=" "x$word_width;
   $word="Push spacebar to start reading";
	$gtk_text = Gtk2::Label->new($word);
	$gtk_text->set_markup($span_black_open.$word.$span_close);
	

	# text label, showing the current sentence
	$gtk_sentence_text = Gtk2::Label->new();
	$gtk_sentence_text->set_markup("sentence nr: ");

	# horizontal box for the control buttons
   if($full_ui){
	  $hbox = Gtk2::HBox->new(FALSE, 10);
	  $hbox->pack_start($pause_button, FALSE, FALSE, 0);
	  $hbox->pack_start($back_button, FALSE, FALSE, 0);
	  $hbox->pack_start($forward_button, FALSE, FALSE, 0);
	  $hbox->pack_start(Gtk2::VSeparator->new(), FALSE, FALSE, 4);
	  $hbox->pack_start($slower_button, FALSE, FALSE, 0);
	  $hbox->pack_start($faster_button, FALSE, FALSE, 0);
	  $hbox->pack_start($gtk_speed_label, FALSE, FALSE, 0);
	  $hbox->pack_start(Gtk2::VSeparator->new(), FALSE, FALSE, 4);
	  $hbox->pack_start($gtk_sentence_text, FALSE, FALSE, 0);

	  # vertical box for the rest
	  $vbox = Gtk2::VBox->new(FALSE, 10);

	  $vbox->pack_start($hbox,FALSE,FALSE,4);
	  $vbox->pack_start(Gtk2::HSeparator->new(),FALSE,FALSE,4);

	  $vbox->pack_start($gtk_text, TRUE, TRUE, 5);
	  $vbox->pack_start(Gtk2::HSeparator->new(),FALSE,FALSE,4);
	  $vbox->pack_start($quit_button, FALSE, FALSE, 0);
   } else {
     my $color = Gtk2::Gdk::Color->parse($bg_color);
     $window->modify_bg('normal', $color);

	  $vbox = Gtk2::VBox->new(FALSE, 10);
	  $vbox->pack_start($gtk_text, TRUE, TRUE, 5);
   } 


	$window->add($vbox);

   # bind keyboard events
   $window->signal_connect('key-press-event' => \&keyevent);

	# show window and start gtk main
	$window->show_all;
	Gtk2->main;

	return TRUE;
}

main();


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
