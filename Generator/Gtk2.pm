package QWizard::Generator::Gtk2;

use strict;
my $VERSION = '2.2.2';
use Gtk2 -init;
require Exporter;
use QWizard::Generator;

@QWizard::Generator::Gtk2::ISA = qw(Exporter QWizard::Generator);

# use strict yells if we use an unquoted FALSE
use Glib qw(FALSE TRUE);

my $have_gd_graph = eval { require GD::Graph::lines; };

sub new {
    my $type = shift;
    my ($class) = ref($type) || $type;
    my $self = {'keep_working_hook' => \&QWizard::Generator::backup_params};
    bless($self, $class);
    $self->add_handler('text',\&QWizard::Generator::Gtk2::do_entry,
		       [['single','name'],
			['default'],
			['forced','0'],
			['single','size'],
			['single','maxsize'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('checkbox',\&QWizard::Generator::Gtk2::do_checkbox,
		       [['multi','values'],
			['default'],
			['single','name'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('label',
		       \&QWizard::Generator::Gtk2::do_label,
		       [['multi','values']]);
    $self->add_handler('radio',
		       \&QWizard::Generator::Gtk2::do_radio,
		       [['values,labels', "   "],
			['default'],
			['single','name'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('paragraph',
		       \&QWizard::Generator::Gtk2::do_paragraph,
		       [['multi','values'],
			['single','preformatted'],
			['single','width']]);
    $self->add_handler('hidetext',\&QWizard::Generator::Gtk2::do_entry,
		       [['single','name'],
			['default'],
			['forced','1'],
			['single','size'],
			['single','maxsize'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('textbox',\&QWizard::Generator::Gtk2::do_textbox,
		       [['single','name'],
			['default'],
			['single','size'],
			['single','maxsize'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('menu',
		       \&QWizard::Generator::Gtk2::do_menu,
		       [['values,labels'],
			['default'],
			['single','name'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('unknown',
		       \&QWizard::Generator::Gtk2::do_unknown,
		       []);
    $self->add_handler('table',
		       \&QWizard::Generator::Gtk2::do_table,
		       [['norecurse','values'],
			['norecurse','headers']]);
    $self->add_handler('bar',
		       \&QWizard::Generator::Gtk2::do_bar,
		       [['norecurse','values']]);
    $self->add_handler('image',
		       \&QWizard::Generator::Gtk2::do_image,
		       [['norecurse','imgdata'],
			['norecurse','image'],
			['single','imagealt']]);
    $self->add_handler('graph',
		       \&QWizard::Generator::Gtk2::do_graph,
		       [['norecurse','values'],
			['norecursemulti','graph_options']]);
    $self->add_handler('multi_checkbox',
		       \&QWizard::Generator::Gtk2::do_multicheckbox,
		       [['multi','default'],
			['values,labels']]);
    $self->add_handler('button',
		       \&QWizard::Generator::Gtk2::do_button,
		       [['single','values'],
			['default']]);
    # XXX: proper fileupload widget
    $self->add_handler('fileupload',
		       \&QWizard::Generator::Gtk2::do_fileupload,
		       [['single','name'],
			['default']]);
    # XXX: file upload params
    #[['default','values']]);
    if (0) {
    # XXX: we need to do a real text box


    }
    $self->init_default_storage();
    return $self;
}

sub our_exit {
    Gtk2->main_quit;
    exit;
}

sub create_qw_label {
    my $label = Gtk2::Label->new(shift);
    $label->set_line_wrap(TRUE);
    $label->set_justify('GTK_JUSTIFY_LEFT');
    $label->set_padding(10,4);
    $label->set_alignment(0, .5);
    return $label;
}

sub goto_top {
    my $self = shift;
    $self->{'generator'}->remove_all_table_entries();
    $self->{'qwizard'}->reset_qwizard();
    Gtk2->main_quit();
}

sub call_callbacks {
    # call callbacks
    if (exists($_[0]->{'qwsubwidgets'})) {
	foreach my $subwid (@{$_[0]->{'qwsubwidgets'}}) {
	    # XXX: pass $_[1] or something to remove or is it auto-cleaned?
	    call_callbacks($subwid);
	}
    }
    if (exists($_[0]->{'qwend'})) {
	$_[0]->{'qwend'}->($_[0]);
    }
    # remove widget
    if ($_[1]) {
	$_[1]->remove($_[0]);
    }
}

# for each widget in a table, allow a callback to be run
sub remove_table_entries {
    my $tbl = shift;
    $tbl->foreach(\&call_callbacks, $tbl);
}

# for each of the tables that populated the last screen, allow
# callbacks for each of them to to be run.
sub remove_all_table_entries {
    my $self = shift;
    foreach my $table (@{$self->{'tables'}}) {
	remove_table_entries($table);
    }

    # if we had previous multiple tables, we need to delete all but
    # the first one.
    while ($#{$self->{'removals'}} > 0) {
	my $obj = pop(@{$self->{'removals'}});
	$self->{'vbox'}->remove($obj);
    }
    @{$self->{'tables'}} = ($self->{'tables'}[0]);
    @{$self->{'frames'}} = ($self->{'frames'}[0]);
    @{$self->{'removals'}} = ($self->{'removals'}[0]);
    $self->{'qtable'} = $self->{'tables'}[0];
    $self->{'qframe'} = $self->{'frames'}[0];
}

sub goto_refresh {
    my $self = shift;
    $self->qwparam('redo_screen',1);
    $self->goto_next(@_);
}

sub goto_next {
    my $self = shift;
    if ($self->{'qbuttonname'}) {
	$self->{'generator'}->qwparam($self->{'qbuttonname'},
				      $self->{'qbuttonval'});
    }
    $self->{'generator'}->remove_all_table_entries();
    Gtk2->main_quit();
}

sub goto_prev {
    my ($self) = @_;
    $self->{'generator'}->revert_params();
    $self->{'generator'}->remove_all_table_entries();
    Gtk2->main_quit();
}

sub our_mainloop {
    my ($self, $wiz, $p) = @_;
    $self->{'window'}->show_all;
    if ($self->{'nointro'}) {
	$self->{'introframe'}->hide;
	$self->{'gtk2intro'}->hide;
    }
    if ($self->qwparam('allow_refresh') ||
	$wiz->{'allow_refresh'} ||
	$p->{'allow_refresh'}) {
	$self->{'refreshbut'}->show();
    } else {
	$self->{'refreshbut'}->hide();
    }
    Gtk2->main;
}

sub add_qframe {
    my ($self, $title) = @_;
    $self->{'qtable'} = Gtk2::Table->new(3, $self->{'qtable_height'}, FALSE);
    push @{$self->{'tables'}}, $self->{'qtable'};
    if (defined($title)) {
	$self->{'qframe'} = Gtk2::Frame->new($title);
	$self->{'qframe'}->set_border_width(5);
	$self->{'qtable_height'} = 10;
	$self->{'qframe'}->add($self->{'qtable'});
	$self->{'vbox'}->pack_start($self->{'qframe'}, FALSE, FALSE, 0);
	push @{$self->{'frames'}}, $self->{'qframe'};
	push @{$self->{'removals'}}, $self->{'qframe'};
    } else {
	$self->{'vbox'}->pack_start($self->{'qtable'}, FALSE, FALSE, 0);
	push @{$self->{'removals'}}, $self->{'qtable'};
    }
}


sub init_screen {
    my ($self, $wiz, $title) = @_;
    if (!$self->{'window'}) {
	$self->{'window'} = Gtk2::Window->new('toplevel');
	$self->{'window'}->set_title($title);
	$self->{'window'}->set_border_width(5);
	$self->{'window'}->set_default_size(600,650);
	$self->{'window'}->signal_connect(delete_event => \&our_exit);
	$self->{'window'}->signal_connect(destroy => \&our_exit);
	
	
	$self->{'parentvbox'} = Gtk2::VBox->new(FALSE, 6);
	$self->{'window'}->add($self->{'parentvbox'});

	# the top bar: XXX should be outside the frame
	$self->{'topbar'} = Gtk2::Table->new(4,4,FALSE);
	$self->{'parentvbox'}->pack_start($self->{'topbar'}, FALSE, FALSE, 0);

	# the title name
	$self->{'gtk2title'} = Gtk2::Label->new($title);
	$self->{'parentvbox'}->pack_start($self->{'gtk2title'},
					  FALSE, FALSE, 0);

	$self->{'scrolledwindow'} = Gtk2::ScrolledWindow->new();
	$self->{'parentvbox'}->pack_start($self->{'scrolledwindow'},
					  TRUE, TRUE, 0);
	$self->{'vbox'} = Gtk2::VBox->new(FALSE, 6);
	$self->{'scrolledwindow'}->add_with_viewport($self->{'vbox'});
	$self->{'introframe'} = Gtk2::Frame->new();
	$self->{'gtk2intro'} = create_qw_label('');
	$self->{'introframe'}->add($self->{'gtk2intro'});
	$self->{'vbox'}->pack_start($self->{'introframe'}, FALSE, FALSE, 0);

	$self->add_qframe('Questions');
    }
}

sub do_ok_cancel {
  my ($self, $nexttext, $wiz, $p) = @_;
  if (!$self->{'bot'}) {
      $self->{'bot'} = Gtk2::HBox->new (FALSE, 6);
      $self->{'bot'}->set_border_width(3);
      $self->{'parentvbox'}->pack_start($self->{'bot'}, FALSE, FALSE, 0);

      if (!$self->{'prevbut'}) {
	  $self->{'prevbut'} = Gtk2::Button->new($wiz->{'back_text'} || 
						 'Back');
	  $self->{'bot'}->pack_start($self->{'prevbut'}, FALSE, FALSE, 0);
	  $self->{'prevbut'}->signal_connect(clicked => \&goto_prev);
	  $self->{'prevbut'}->{'generator'} = $self;
      }
      if (!$self->{'nextbut'}) {
	  $self->{'nextbut'} = Gtk2::Button->new($nexttext ||
						 $wiz->{'next_text'} ||
						 'Next');
	  $self->{'bot'}->pack_start($self->{'nextbut'}, FALSE, FALSE, 0);
	  $self->{'nextbut'}->signal_connect(clicked => \&goto_next);
	  $self->{'nextbut'}->{'generator'} = $self;
      }
      if (!$self->{'refreshbut'}) {
	  $self->{'refreshbut'} = Gtk2::Button->new('Refresh');
	  $self->{'bot'}->pack_start($self->{'refreshbut'}, FALSE, FALSE, 0);
	  $self->{'refreshbut'}->signal_connect(clicked => \&goto_refresh);
	  $self->{'refreshbut'}->{'generator'} = $self;
      }
      if (!$self->{'canbut'}) {
	  $self->{'canbut'} = 
	    Gtk2::Button->new($wiz->qwparam('QWizard_Cancel') ||
			      $wiz->{'cancel_text'} || 'Cancel');
	  $self->{'bot'}->pack_end($self->{'canbut'}, FALSE, FALSE, 0);
	  $self->{'canbut'}->signal_connect(clicked => \&goto_top);
	  $self->{'canbut'}->{'generator'} = $self;
	  $self->{'canbut'}->{'qwizard'} = $wiz;
      }
  } else {
      $self->{'nextbut'}->set_label($nexttext || 'Ok');
  }
}


# put stuff at a particular spot in the current table
sub put_it {
    my ($self, $w, $row, $col) = @_;
    if (!$row) {
	if (exists($self->{'currentrow'}) && defined($self->{'currentrow'})) {
	    $row = $self->{'currentrow'};
	} else {
	    $row = $self->{'currentq'};
	}
    }
    if (!$col) {
	if (exists($self->{'currentcol'}) && defined($self->{'currentcol'})) {
	    $col = $self->{'currentcol'};
	} else {
	    $col = 2;
	}
    }

    # remove the temp assignments

    if (ref($w) eq '') {
	$w = create_qw_label($w);
	$w->set_alignment(0, 0) if ($col == 1);
    }

    # place the item in the table
    $self->{'qtable'}->attach($w, $col, $col+1, $row, $row+1,
			      ($col == 1 ? [qw(fill)] : [qw(fill expand)]),
			      ($col == 1 ? [qw(fill)] : [qw(fill expand)]),
			      ($col == 1 ? 5 : 0),
			      0);
    $self->{'lastwidget'} = $w;

#     # bind the tab and alt-tab key presses to forward and backward widgets
#     if (ref($w) =~ /Entry|Menu|Text|Button|Checkbutton|Radio|Optionmenu/) {
# 	if ($self->{'lastw'}) {
# 	    $self->{'lastw'}->bind('<Tab>',[\&tab_next, $w, $self]);
# 	    $w->bind('<Alt-Key-Tab>',[\&tab_next, $self->{'lastw'}, $self]);
# 	}
# 	$self->{'lastw'} = $w;
#     }
}

sub set_default {
    my ($self, $q, $def) = @_;
    $self->qwparam($q->{'name'}, $def) if ($def && $self->qwparam($q->{'name'}) ne $def);
}

######################################################################
# QWizard functions for doing stuff.

sub wait_for {
  my ($self, $wiz, $next, $p) = @_;
  $self->do_ok_cancel($next, $wiz, $p);
  $self->our_mainloop($wiz, $p);
  return 1;
}

sub do_error {
    my ($self, $q, $wiz, $p, $err) = @_;
    $self->{'currentq'}++;
    $self->{'qadd'}++;
    # XXX: make font red
    my $lb = create_qw_label($err);
    $lb->set_markup("<span weight=\"bold\" foreground=\"red\">$err</span>");
    $self->put_it($lb, undef, 1);
}

sub do_question {
    my ($self, $q, $wiz, $p, $text, $qcount) = @_;
    my $top = $self->{'qtable'};
    my $l;
    $self->{'currentq'} = $qcount + $self->{'qadd'};

    if ($q->{'helpdesc'} && !$self->qwpref('usehelpballons')) {
	my $f = Gtk2::VBox->new();

	#
	# Get the actual help text, in case this is a subroutine.
	#
	my $helptext = $q->{'helpdesc'};
	if (ref($helptext) eq "CODE") {
	    $helptext = $helptext->();
	}

	$f->pack_start(create_qw_label($text), FALSE,FALSE,0);
	$f->pack_start(create_qw_label($helptext), FALSE,FALSE,0);
	$self->put_it($f, undef, 1);
    } else {
	# XXX: help bubble?
	$l = create_qw_label($text);
	$l->set_alignment(0, 0);
	$self->put_it($l, undef, 1);
    }
}

sub start_questions {
    my ($self, $wiz, $p, $title, $intro) = @_;
    $self->{'gtk2title'}->set_markup("<span size=\"x-large\" underline=\"single\">$title</span>");
#    $self->{'gtk2title'}->set_pattern("_" x length($title));
    if ($intro) {
	$self->{'gtk2intro'}->set_label($intro);
	$self->{'nointro'} = 0;
    } else {
	# GRR...  can't hide here since a show_all comes later.
	$self->{'gtk2intro'}->set_label('');
	$self->{'nointro'} = 1;
    }

    $self->{radiogroups} = {};
	
    return;
    # XXX: intro
    $self->{'qintro'}->delete('1.0','end');
    if ($intro) {
	$self->{'qintro'}->configure(-height => length($intro)/80 + 1);
	$self->{'qintro'}->insert('end',$intro);
    } else {
	$self->{'qintro'}->configure(-height => 0);
    }
}

sub end_questions {
    my $self = shift;
    # this makes us keep adding new table rows during a merge
    $self->{'qadd'} = $self->{'currentq'} + 1;
    $self->{'lastw'} = undef;
}


##################################################
# widgets
##################################################

sub start_bar {
    my ($self, $wiz, $name) = @_;

    $self->add_qframe($name);
    $self->{'inbar'} = 1;
}

sub end_bar {
    my ($self, $wiz, $name) = @_;

    $self->add_qframe($name);
    delete($self->{'inbar'});
}

sub do_bar {
    my ($self, $q, $wiz, $p, $widgets) = @_;

    $self->start_bar($wiz, undef);
    $self->do_a_table([$widgets], $self->{'qtable'}, -1, $wiz, $q, $p);
    $self->end_bar($wiz, 'Questions');
}

sub do_top_bar {
    my ($self, $q, $wiz, $p, $widgets) = @_;

    my $oldtable = $self->{'qtable'};
    $self->{'qtable'} = $self->{'topbar'};
    push @{$self->{'tables'}}, $self->{'qtable'};
    $self->do_a_table([$widgets], $self->{'qtable'}, -1, $wiz, $q, $p);
    $self->{'qtable'} = $oldtable;
}

sub do_button {
    my ($self, $q, $wiz, $p, $vals, $def) = @_;
    my $but = Gtk2::Button->new($vals);
    $but->signal_connect(clicked => \&goto_next);
    $but->{'qbuttonname'} = $q->{'name'};
    $but->{'qbuttonval'} = $def;
    $but->{'generator'} = $self;
    $self->put_it($but);
}

sub do_fileupload {
    my ($self, $q, $wiz, $p, $name, $def) = @_;

    # A file upload box is created via a button to request a file.

    my $but = Gtk2::Button->new($def || 'Select File...');
    $but->signal_connect(clicked => \&create_fileupload_screen);
    $but->{'qbuttonname'} = $q->{'name'};
    $but->{'qbuttonval'} = $def;
    $but->{'generator'} = $self;
    $but->{'parent_button'} = $but;
    $self->put_it($but);
}

sub create_fileupload_screen {
    my $parent_button = shift;

    # create the widget screen
    my $fs = Gtk2::FileSelection->new("Select a file");

    # define the action for the Ok button.
    my $ok = $fs->ok_button;
    $ok->{'pwidget'} = $fs;
    $ok->{'generator'} = $parent_button->{'generator'};
    $ok->{'qwname'} = $parent_button->{'qbuttonname'};
    $ok->{'parent_button'} = $parent_button;
    $ok->signal_connect('clicked' =>
			   sub {
			       my $val = $_[0]{'pwidget'}->get_filename();
			       # save the value
			       $_[0]->{'generator'}->qwparam($_[0]->{'qwname'},
							     $val);
			       # close the widget
			       $_[0]->{'pwidget'}->hide_all;

			       # change the button text
			       # (truncate just to file name first).
			       $val =~ s/.*\///;
			       $_[0]->{'parent_button'}->set_label($val);
			   });

    # define the action for the Cancel button.
    my $can = $fs->cancel_button;
    $can->{'pwidget'} = $fs;
    $can->{'generator'} = $parent_button->{'generator'};
    $can->{'qwname'} = $parent_button->{'qwname'};
    $can->signal_connect('clicked' =>
			   sub {
			       # close the widget
			       $_[0]->{'pwidget'}->hide_all;
			   });
    $fs->show_all;
}

sub check_callback {
    if ($_[0]->get_active) {
	$_[0]->{'generator'}->qwparam($_[0]->{'qwname'},
				      $_[0]->{'qwvals'}[0]);
    } else {
	$_[0]->{'generator'}->qwparam($_[0]->{'qwname'},
				      $_[0]->{'qwvals'}[1]);
    }
}

sub do_checkbox {
    my ($self, $q, $wiz, $p, $vals, $def, $name,
	$submit, $refresh_on_change) = @_;
    $vals = [1, 0] if ($#$vals == -1);
    my $cb = Gtk2::CheckButton->new();
    if ($def eq $vals->[0]) {
	$cb->set_active(TRUE);
    }
    @{$cb->{'qwvals'}} = @$vals;
    $cb->{'generator'} = $self;
    $cb->{'qwname'} = $name;
    $cb->{'qwend'} = \&check_callback;
    if ($submit) {
	$cb->signal_connect(clicked => \&goto_next);
    }
    if ($refresh_on_change) {
	$cb->signal_connect(clicked => \&goto_refresh);
    }
    $self->put_it($cb);
    $self->set_default($q, $def);
}

# set all buttons to on
sub set_all_boxes {
    my $wid = shift;
    my $checkboxes = $wid->{'boxes'};
    foreach my $checkbox (@$checkboxes) {
	$checkbox->set_active(TRUE);
    }
}

# set all buttons to on
sub unset_all_boxes {
    my $wid = shift;
    my $checkboxes = $wid->{'boxes'};
    foreach my $checkbox (@$checkboxes) {
	$checkbox->set_active(FALSE);
    }
}

# set all buttons to on
sub toggle_all_boxes {
    my $wid = shift;
    my $checkboxes = $wid->{'boxes'};
    foreach my $checkbox (@$checkboxes) {
	if ($checkbox->get_active) {
	    $checkbox->set_active(FALSE);
	} else {
	    $checkbox->set_active(TRUE);
	}
    }
}

sub do_multicheckbox {
    my ($self, $q, $wiz, $p, $defs, $vals, $labels) = @_;
    my $tf = Gtk2::VBox->new(FALSE, 3);
    my $count = -1;
    my @buts;
    foreach my $v (@$vals) {
	$count++;
	my $l = (($labels->{$v}) ? $labels->{$v} : "$v");
	my $lb = create_qw_label($l);
	my $c = Gtk2::CheckButton->new();
	my $hb = Gtk2::HBox->new(FALSE, 0);

	$hb->pack_start($c, FALSE, FALSE, 0);
	$hb->pack_start($lb, FALSE, FALSE, 0);
	$tf->pack_start($hb, FALSE, FALSE, 0);
	
	if ($defs->[$count] eq $v) {
	    $c->set_active(TRUE);
	}
	$c->{'qwvals'} = [$v,undef];
	$c->{'generator'} = $self;
	$c->{'qwname'} = $q->{'name'} . $v;
	$c->{'qwend'} = \&check_callback;
	push @buts, $c;
	
	push @{$wiz->{'passvars'}},$q->{'name'} . $v;
	push @{$tf->{'qwsubwidgets'}}, $c;
	$self->{'datastore'}->set($v, $defs->[$count]);
    }

    if ($q->{'notoggles'}) {
	my $hb = Gtk2::HBox->new(FALSE, 0);

	my $but = Gtk2::Button->new('Set All');
	$but->signal_connect(clicked => \&set_all_boxes);
	$but->{'boxes'} = \@buts;
	$hb->pack_start($but, FALSE, FALSE, 0);

	$but = Gtk2::Button->new('Unset All');
	$but->signal_connect(clicked => \&unset_all_boxes);
	$but->{'boxes'} = \@buts;
	$hb->pack_start($but, FALSE, FALSE, 0);

	$but = Gtk2::Button->new('Toggle All');
	$but->signal_connect(clicked => \&toggle_all_boxes);
	$but->{'boxes'} = \@buts;
	$hb->pack_start($but, FALSE, FALSE, 0);

	$tf->pack_start($hb, FALSE, FALSE, 0);
    }

    $self->put_it($tf);
}

sub do_radio {
    my ($self, $q, $wiz, $p, $vals, $labels, $def, $name,
	$submit, $refresh_on_change) = @_;

    my $vb = Gtk2::VBox->new();
    my (@ws);
    foreach my $v (@$vals) {
	my $text = (($labels->{$v}) ? $labels->{$v} : "$v");
	my $rb = Gtk2::RadioButton->new($self->{'radiogroups'}{$name}, $text);
	if ($v eq $def) {
	    $rb->set_active(TRUE);
	}
	$rb->{'qwname'} = $name;
	$rb->{'generator'} = $self;
	$rb->{'qwvalue'} = $v;
	push @ws, $rb;
	if ($submit) {
	    $rb->signal_connect(clicked => \&goto_next);
	}
	if ($refresh_on_change) {
	    $rb->signal_connect(clicked => \&goto_refresh);
	}
	$vb->pack_end($rb, FALSE, FALSE, 0);
	$self->{'radiogroups'}{$name} = $rb->get_group();
    }
    $vb->{'rwidgets'} = \@ws;
    $vb->{'qwend'} = sub {
	foreach my $w (@{$_[0]->{'rwidgets'}}) {
	    if ($w->get_active()) {
		$w->{'generator'}->qwparam($w->{'qwname'}, $w->{'qwvalue'});
		last;
	    }
	}
    };
    $self->put_it($vb);
    $self->set_default($q, $def);
}

sub do_label {
    my ($self, $q, $wiz, $p, $vals, $def) = @_;
    if (defined ($vals)) {
	foreach my $i (@$vals) {
	    $self->put_it($i);
	}
    }
}

sub do_paragraph {
    my ($self, $q, $wiz, $p, $vals, $preformatted, $width) = @_;
    my $w = $width || 40;
    foreach my $i (@$vals) {
	my $t;
	$t = create_qw_label($i);
	if ($preformatted) {
	    $t->set_line_wrap(FALSE)
	} else {
	    # XXX use width argument to define where to wrap
	    $t->set_line_wrap(TRUE)
	}
	$self->put_it($t);
    }
}

sub do_menu {
    my ($self, $q, $wiz, $p, $vals, $labels, $def, $name,
	$submit, $refresh_on_change) = @_;

    my $optionmenu = Gtk2::OptionMenu->new();
    $optionmenu->{'generator'} = $self;
    $optionmenu->{'qwname'} = $name;
    my $menu = Gtk2::Menu->new();

    my $h = 0;
    my $activem;
    my $activenum = 0;
    foreach my $v (@$vals) {
	my $mitem;
	if ($labels->{$v}) {
	    $mitem = Gtk2::MenuItem->new($labels->{$v});
	} else {
	    $mitem = Gtk2::MenuItem->new($v);
	}
	if ((defined($def) && $def eq $v) ||
	    (!$def && !exists($optionmenu->{'finalval'}))) {
	    $activem = $mitem;
	    $activenum = $h;
	    $optionmenu->{'finalval'} = $v;
	    $mitem->{'nosubmityet'} = 1;
	}
	$mitem->{'qwvalue'} = $v;
	$mitem->{'finalvalref'} = \$optionmenu->{'finalval'};
	$mitem->{'submit'} = $submit;
	$mitem->{'refresh_on_change'} = $refresh_on_change;
	$mitem->{'generator'} = $self;
 	$mitem->signal_connect('activate' =>
 			       sub {
				   # set the final value upon selection
 				   ${$_[0]->{'finalvalref'}} =
 				     $_[0]->{'qwvalue'};

				   # auto-submit requested (unless
				   # still setting up).
				   goto_next($_[0])
				     if ($_[0]->{'submit'} &&
					 !$_[0]->{'nosubmityet'});
				   # refresh on change requested (unless
				   # still setting up).
				   goto_refresh($_[0])
				     if ($_[0]->{'refresh_on_change'} &&
					 !$_[0]->{'nosubmityet'});
 			       });
	
	$menu->attach($mitem, 0, 1, $h, $h+1);
	$h++;
    }

    $optionmenu->{'qwend'} = sub {
	$_[0]->{'generator'}->qwparam($_[0]->{'qwname'}, $_[0]->{'finalval'});
    };
    $optionmenu->set_menu($menu);
    $self->put_it($optionmenu);
    if ($activem) {
	$menu->set_active($activenum);
	$menu->activate_item($activem, 1);
	delete $activem->{'nosubmityet'};
    }
    $self->set_default($q, $def);
}

sub do_entry {
    my ($self, $q, $wiz, $p, $name, $def, $hide) = @_;

    my $e = Gtk2::Entry->new();
    $e->set_text($def);
    $e->{'qwend'} = sub { 
	$_[0]->{'generator'}->qwparam($name, $_[0]->get_text());
    };
    $e->{'generator'} = $self;

    #
    # Set up a value to use if the text shouldn't be echoed to the screen.
    #
    if ($hide) {
	$e->set_invisible_char("*");
	$e->set_visibility(FALSE);
    }

    $self->put_it($e);
    $self->set_default($q, $def);
}

sub do_textbox {
    my ($self, $q, $wiz, $p, $name, $def) = @_;

    my $tb = Gtk2::TextBuffer->new();
    $tb->set_text($def);
    my $tv = Gtk2::TextView->new_with_buffer($tb);
    $tv->set_size_request(-1,150);
    $tv->{'qwend'} = sub { 
	my @bounds = $_[0]->get_buffer()->get_bounds();
	$_[0]->{'generator'}->qwparam($_[0]->{'qwname'},
				      $_[0]->get_buffer()->get_text(@bounds, TRUE));
    };
    $tv->{'generator'} = $self;
    $tv->{'qwname'} = $name;

    $self->put_it($tv);
    $self->set_default($q, $def);
}

sub do_separator {
    my ($self, $q, $wiz, $p, $text) = @_;
    my $where = $self->{'qf'};
    $self->{'currentq'}++;
    $self->{'qadd'}++;
    my $lab = Gtk2::Label->new();
    $self->put_it($lab);
}

##################################################
# Display
##################################################

sub do_a_table_widget {
    my ($self, $wiz, $p, $table, $column, $colnum, $rowc) = @_;

    my $oldqt = $self->{'qtable'};
    $self->{'qtable'} = $table;

    my $oldq = $self->{'currentq'};

    my $oldrow = $self->{'currentrow'};
    $self->{'currentrow'} = $rowc;

    my $oldc = $self->{'currentcol'};
    $self->{'currentcol'} = $colnum;
		
    my $subname = $wiz->ask_question($p, $column);
    push @{$wiz->{'passvars'}}, $subname if ($subname);
    push @{$table->{'qwsubwidgets'}}, $self->{'lastwidget'};

    $self->{'qtable'} = $oldqt;
    $self->{'currentq'} = $oldq;
    if ($oldc) {
	$self->{'currentcol'} = $oldc 
    } else {
	delete $self->{'currentcol'};
    }
    if ($oldrow) {
	$self->{'currentrow'} = $oldrow 
    } else {
	delete $self->{'currentrow'};
    }
}


sub do_a_table {
    my ($self, $table, $parentt, $rowc, $wiz, $q, $p) = @_;

    foreach my $row (@$table) {
	my $col = 0;
	$rowc++;
	foreach my $column (@$row) {
	    if (ref($column) eq "ARRAY") {
		# sub table
		my $newt = Gtk2::Table->new(4,4,FALSE);
		$self->do_a_table($column, $newt, -1, $wiz, $q, $p);
		$parentt->attach_defaults($newt, $col, $col+1, $rowc, $rowc+1);
		$col++;
		push @{$parentt->{'qwsubwidgets'}}, $newt;
	    } elsif (ref($column) eq "HASH") {
		$self->do_a_table_widget($wiz, $p, $parentt, $column,
					 $col++, $rowc);
	    } else {
		$parentt->attach_defaults(create_qw_label($column),
					  $col, $col + 1, $rowc, $rowc+1);
		$col++;
	    }
	}
    }
}

sub do_table {
    my ($self, $q, $wiz, $p, $table, $headers) = @_;

    my $fixed = ($headers) ? 1 : 0;

    my $tab = Gtk2::Table->new(4,4,FALSE);
    $tab->set_border_width(4);

    if ($headers) {
	my $col = 0;
	foreach my $column (@$headers) {
	    # XXX: mark up bold?
	    $tab->attach_defaults(create_qw_label($column),
				  $col, $col+1, 0, 1);
	    $col++;
	}
    }

    $self->do_a_table($table, $tab, $fixed-1, $wiz, $q, $p);
    $self->put_it($tab);
}

sub do_graph {
    my $self = shift;
    my ($q, $wiz, $p, $data, $gopts) = @_;

    # a graph is really a file with a special generator.
    $self->do_image($q, $wiz, $p, $self->do_graph_data(@_), undef, "[graph]");
}

##############################################
#
sub scale_img {
    my $but = shift;
    my $img = $but->{'img'};
    my $gdimg = $img->{'origpixbuf'};

    # get curernt image size
    my $wid = $gdimg->get_width();
    my $hei = $gdimg->get_height();

    # set the total image size to the sum of all button presses
    $img->{'currentsize'} += $but->{'scale'};
    $img->{'currentsize'} = 0 if ($img->{'currentsize'} < 0);

    $gdimg =
      $gdimg->scale_simple($wid * $img->{'currentsize'},
			   $hei * $img->{'currentsize'}, 'GDK_INTERP_NEAREST');
#     $wid = $gdimg->get_width();
#     $hei = $gdimg->get_height();
    $img->set_from_pixbuf($gdimg);
#     print "img: $wid x $hei","\n";
}

sub orig_size {
    my $but = shift;
    my $img = $but->{'img'};
    my $gdimg = $img->{'origpixbuf'};
    $img->{'scale'} = 1;
    $img->set_from_pixbuf($img->{'origpixbuf'});
}

sub create_scale_but {
    my ($hb, $lab, $dist, $img) = @_;

    my $but = Gtk2::Button->new($lab);
    $but->signal_connect(clicked => \&scale_img);
    $but->{'img'} = $img;
    $but->{'scale'} = $dist;
    $hb->pack_end($but, FALSE, FALSE, 0);
}

sub do_image {
	my $self = shift;
	my ($q, $wiz, $p, $datastr, $filestr, $imgalt) = @_;

	my $img;
	if (1) {
	    if ($datastr) {
		# XXX: data hand handled yet.
		$filestr = $self->create_temp_file('.png',$datastr);
	    } else {
		$filestr = $wiz->{'generator'}{'imagebase'} . $filestr;
	    }
	    # image file
	    $img = Gtk2::Image->new_from_file($filestr);
	}
	if ($img) {
	    my $vb = Gtk2::VBox->new();
	    my $hb = Gtk2::HBox->new();

	    create_scale_but($hb, "25% >", .25, $img);
	    create_scale_but($hb, "10% >", .1, $img);

	    my $but = Gtk2::Button->new("Original Size");
	    $but->signal_connect(clicked => \&orig_size);
	    $hb->pack_end($but, FALSE, FALSE, 0);

	    create_scale_but($hb, "< 10%", -.1, $img);
	    create_scale_but($hb, "< 25%", -.25, $img);

	    $vb->pack_end($hb, FALSE, FALSE, 0);
	    $vb->pack_end($img, FALSE, FALSE, 0);

	    $img->{'currentsize'} = 1;
	    my ($arg1, $arg2) = $img->get_pixbuf();

	    $img->{'origpixbuf'} = $arg1;
	    $but->{'img'} = $img;

	    $self->put_it($vb);
	} else {
	    $self->put_it(Gtk2::Label->new($imgalt || "Broken Image"));
	}
}

##################################################
# Trees
##################################################

sub do_tree {
    my ($self, $q, $wiz, $p, $labels) = @_;

    my $tv = new Gtk2::TreeView();
    my $mod = new Gtk2::TreeStore('Glib::String');
    $tv->set_model($mod);

    my @expand;
    if ($q->{'default'}) {
	#ensure that the default is initially visible
	my $cur = $q->{'default'};
	unshift @expand, $cur;
	until ($cur eq $q->{'root'}) {
	    $cur = get_name($q->{'parent'}->($wiz, $cur));
	    unshift @expand, $cur;
	}
	$self->{'datastore'}->set($q->{'name'},$q->{'default'}) if $q->{'name'};
    }

    #
    # remember a bunch of important stuff in the view
    #
    $mod->{'qwdata'}{'qw'} = $wiz;
    $mod->{'qwdata'}{'q'} = $q;
    $mod->{'qwdata'}{'labels'} = $labels;
    $mod->{'qwdata'}{'datamap'}{'0'} = $q->{'root'};

    #
    # add the root node
    #
    my $iter = $mod->append(undef);
    $mod->set($iter, 0, $q->{'root'});
    $mod->append($iter); # add bogus child

    #
    # When a row expands, add all the children
    #
    $tv->signal_connect("row-expanded",
			sub {
			    my ($treeview,$piter,$path) = @_;
			    $self->add_children($treeview, $piter,
						$path->to_string());
			});

    #
    # When a row collapses, remove the sub data (probably not needed
    # but cleaner and removes memory)
    #
    $tv->signal_connect("row-collapsed",
			sub {
			    # remove all children from the tree
			    my ($treeview,$iter,$path) = @_;

			    my $model = $treeview->get_model();

			    # remove children
			    while (my $i = $model->iter_children($iter)) {
				$model->remove($i);
			    }

			    # attach a bogus one to enuser the
			    # parent has the hierarchial widget
			    # still.
			    $model->append($iter);

			    return 1;
			});

    #
    # when the cursor changes, we pick this as our select value
    #
    $tv->signal_connect("cursor-changed",
			sub {
			    my ($path, $col) = $_[0]->get_cursor();
			    my $mod = $_[0]->get_model();
			    my $qname = $mod->{'qwdata'}{'q'}{'name'};
			    my $pname = $path->to_string();
			    my $val = $mod->{'qwdata'}{'datamap'}{$pname};
			    $mod->{'qwdata'}{'qw'}->qwparam($qname, $val);
			});


    #
    # Add the rendering type
    #
    my $col = Gtk2::TreeViewColumn->new;
    $col->set_title("Name");

    my $cell = Gtk2::CellRendererText->new;
    $col->pack_start ($cell, 1);
    $col->add_attribute ($cell, text => 0);
    $tv->append_column($col);

    #
    # Do initial expasion to find the default
    #
    if ($#expand > -1) {
	shift @expand;  # drop the root node
	$tv->{'expand'} = \@expand;
 	$tv->expand_row(new Gtk2::TreePath("0"), FALSE);
	$tv->set_cursor(new Gtk2::TreePath($tv->{'qwdata'}{'cursor'}))
	  if ($tv->{'qwdata'}{'cursor'});
    }

    $self->put_it($tv);
}

sub get_name {
    my $node = shift;

    if (ref($node) eq 'HASH') {
	return $node->{'name'};
    } else {
	return $node;
    }
}

sub add_children {
    my ($self, $tv, $piter, $path) = @_;
    my $model = $tv->get_model();
    my $count = 0;
    my $q = $model->{'qwdata'}{'q'};
    my $wiz = $model->{'qwdata'}{'qw'};
    my $labels = $model->{'qwdata'}{'labels'};
    my $expand = $tv->{'expand'};

    # get a list of children
    my $children = 
      $q->{'children'}->($wiz, $model->{'qwdata'}{'datamap'}{$path});

    if (!$children || $#$children == -1) {
	# probably will never get here if the rest of the code was good...
	$model->remove($model->iter_nth_child($piter, 0));
	return;
    }

    # append the path with new suffixes :N:M:...
    $path .= ":" if ($path ne '');

    # add each child node.
    foreach my $child (@$children) {
	add_node($wiz, $tv, $model, $child, $q, $piter, $labels,
		 $path . "$count");
	$count++;
    }

    # remove bogus node
    $model->remove($model->iter_nth_child($piter, 0));

    # expading further if needed
    $tv->expand_row(new Gtk2::TreePath($tv->{'qwdata'}{'expand_row'}), FALSE);

}

sub add_node {
    my ($wiz, $tv, $model, $node, $q, $piter, $labels, $path) = @_;

    my $label;
    my $name = get_name($node);
    if (ref($node) eq 'HASH') {
	$label = $node->{'label'};
    }

    $label = $label || $labels->{$name} || $name;

    #text of the node is the label. name is the identifier.

    my $child = $model->insert($piter, -1);
    $model->set($child, 0, $label);
    $model->{'qwdata'}{'datamap'}{$path} = $name;

    # test to see if the new node has children
    my $ans = $q->{'children'}->($wiz, $name);

    # add a bogus child to make the drop down widget appear
    $model->insert($child, -1) if ($ans && $#$ans > -1);

    # look to see if we're a child that needs opening in the default pass
    if (defined($tv->{'expand'}) &&
	$#{$tv->{'expand'}} > -1 &&
	$tv->{'expand'}[0] eq $name) {
	shift @{$tv->{'expand'}}; # shift of the current one;

	if ($#{$tv->{'expand'}} == -1) {
	    # this is the last node, selecte it
	    $tv->{'qwdata'}{'cursor'} = $path;
	} else {
	    # tell the sub row to expand
	    $tv->{'qwdata'}{'expand_row'} = $path;
	}
    }
}

##################################################
#
# Automatic updating for monitors.
#

sub do_autoupd
{
	#
	# Dummy routine for now!
	#
	warn "Gtk2.do_autoupd:  currently no automatic updating is defined for Gtk2.  This should be fixed RSN.\n"
}

##################################################
# unknown type errors
#
sub do_unknown {
    my ($self, $q, $wiz, $p) = @_;
    $self->put_it("Unknown question type $q->{type} not handled in primary '$p->{module_name}'.\nIt is highly likely this application will no longer function properly beyond this point.");
}


##################################################
# action confirm
##################################################

sub start_confirm {
    my ($self, $wiz) = @_;

    $self->remove_all_table_entries();
    $self->put_it('Wrapping up.',1,1);
    $self->put_it('Do you want to commit the following changes:',2,1);
    $self->{'resultf'} = create_qw_label('');
    $self->put_it($self->{'resultf'},3,1);
}

sub end_confirm {
    my ($self, $wiz) = @_;
    # this will be deleted by the cancel button if they press it.
    $self->do_hidden($wiz, 'wiz_confirmed', 'Commit');
    $self->do_ok_cancel("Commit", $wiz);
    $self->our_mainloop();
    return 1;
}

sub do_confirm_message {
    my ($self, $wiz, $msg) = @_;
    $self->{'resultf'}->set_text($self->{'resultf'}->get_text() . $msg . "\n");
}

sub canceled_confirm {
    my ($self, $wiz) = @_;
    goto_top();
}

##################################################
# actions
##################################################

sub start_actions {
    my ($self, $wiz) = @_;
    $self->remove_all_table_entries();
    $self->put_it('Processing your request...',1,1);
    $self->{'resultf'} = create_qw_label('');
    $self->put_it($self->{'resultf'},2,1);
}

sub end_actions {
    my ($self, $wiz) = @_;
    $self->put_it('Done',3,1);
    $self->do_ok_cancel("Finish", $wiz);
    $self->clear_params();
    $self->our_mainloop();
    return 1;
}

sub do_action_output {
    my ($self, $wiz, $action) = @_;
    $self->{'resultf'}->set_text($self->{'resultf'}->get_text() . $action . "\n");
}

sub do_action_error {
    my ($self, $wiz, $errstr) = @_;
    # XXX: make red
    $self->{'resultf'}->set_text($self->{'resultf'}->get_text() . $errstr . "\n");
}

1;
