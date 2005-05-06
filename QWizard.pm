package QWizard;

our $VERSION = '2.1';
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(qwdebug qwisdebugon qwparam qwpref qw_upload_fh qw_upload_file
		 qw_required_field qw_integer qw_optional_integer
		 qw_check_int_ranges qw_check_length_ranges
                 qw_hex qw_optional_hex qw_check_hex_and_length);

use Data::Dumper;
our $qwdebug = 0;
our $qwdebug_indent = 0;
our $qwvar;
our $qwcurrent;

our %states = ( ASKING => 1,
		CONFIRMING => 2,
		ACTING => 3,
		FINISHED => 4,
		CANCELED => 5,
	      );

use strict;

sub new {
    my $type = shift;
    $qwdebug_indent = 0;
    my ($class) = ref($type) || $type;
    my $self;
    %$self = @_;
    map { $self->{'primaries'}{$_}{'module_name'} = $_ } 
      keys(%{$self->{'primaries'}});
    if (!$self->{'generator'}) {
	eval { require QWizard::Generator::Best; };
	$self->{'generator'} =
	  new QWizard::Generator::Best(@{$self->{'generator_args'}});
    }

    bless($self, $class);

    $self->qwsetdebug();

    #
    # Get the URI preference option and set our preferences.
    #
    my $npprefs = $self->{'npprefs'};
    $npprefs =~ s/&np-prefs=//;
    parseprefs($self,$npprefs);

    return $self;
}

########################################################################
# parseprefs()
#
# Valid preferences and their values:
#	pref_debug      0, 1
#	pref_history    dont, sidebar, frame
#	pref_intro      0, 1
#
sub parseprefs {
    my $self = shift;			# Me.
    my $prefs = shift;			# Preference argument from URI.
    my @preflist;			# List of preferences.
    my $pcnt;				# Number of preferences.
    my $prefstr;			# Preference string.

    #
    # Break the URI preference argument up into individual preferences.
    #
    @preflist = split(',',$prefs);
    $pcnt = @preflist;

    #
    # Examine each preference individually, ensuring the name and value
    # are both valid.
    #
    for(my $ind=0;$ind<$pcnt;$ind++)
    {
	my @pieces;			# Preference pieces.
	my $prefname;			# Name of preference.
	my $prefval;			# Value of preference.

	@pieces = split('=',$preflist[$ind]);
	$prefname = "pref_" . $pieces[0];
	$prefval  = $pieces[1];

	#
	# Check the validity of the preference name and value.
	#
	if($prefname eq "pref_debug")
	{
		if(($prefval != 0) && ($prefval != 1))
		{
			warn "QW:parseprefs:  invalid value \"$prefval\" for preference \"$prefname\"\n";
			next;
		}
	}
	elsif($prefname eq "pref_history")
	{
		if(($prefval ne "dont") && ($prefval ne "frame") &&
		   ($prefval ne "sidebar"))
		{
			warn "QW:parseprefs:  invalid value \"$prefval\" for preference \"$prefname\"\n";
			next;
		}
	}
	elsif($prefname eq "pref_intro")
	{
		if(($prefval != 0) && ($prefval != 1))
		{
			warn "QW:parseprefs:  invalid value \"$prefval\" for preference \"$prefname\"\n";
			next;
		}
	}
	else
	{
		warn "QW:parseprefs:  unknown preference \"$prefname\"\n";
		next;
	}

	#
	# Set the preference value.
	#
# warn "QW:parseprefs:  setting \"$prefname\" to $prefval\n\n";
	$self->qwpref($prefname,$prefval);
	$self->qwparam($prefname,$prefval);
    }

}

#
# Primary manipulation routines
#
sub get_primary {
    my ($self, $namefull) = @_;

    my $name = drop_remap_prefix($namefull);
    if ($self->{'primaries'}{$name}) {
	return $self->{'primaries'}{$name}
    }
}

sub add_primary {
    my $self = shift;
    my $name = shift;
    my %primary = @_;

    $self->{'primaries'}{$name} = \%primary;
    $self->{'primaries'}{$name}{'name'} = $name
      if (!$self->{'primaries'}{$name}{'name'});
    return \%primary;
}

sub merge_primaries {
    my $self = shift;
    my $primaries = shift;
    foreach my $i (keys(%$primaries)) {
	$self->{'primaries'}{$i} = $primaries->{$i};
	$self->{'primaries'}{$i}{'name'} = $i
	  if (!$self->{'primaries'}{$i}{'name'});
    }
}


#
# Functions that actually do the work
#
sub magic {
  my $self = shift;

  $self->{'last_screen'} = 0;

  do {
      qwdebug("------------------------------------------------------------------");
      qwdebug("incoming: " . ref($self->{'generator'}) . " :" 
	      . $self->qwparam('pass_vars'));
      qwdebug("incoming variables: " . $self->qwparam('pass_vars'));
      qwdebug("incoming stack: " . $self->qwparam('qwizard_tree'));
      if ($self->qwparam('disp_help_p')) {
	  $self->display_help();
      } elsif ($self->qwparam('pass_vars')) {
	  qwdebug("called with an existing todo list, continuing to work.");
	  $self->keep_working(@_);
	  qwdebug("done calling existing");
      } else {
	  qwdebug("starting with the default list of primaries.\n");
	  $self->do_named_primaries(@_);
	  qwdebug("done with the default list of primaries.\n");
      }
  } while ((!$self->{'last_screen'} && !$self->{'one_pass'} && 
	    !$self->{'generator'}{'one_pass'}));
}

sub do_named_primaries {
    my $self = shift;
    my $top = {};
    $top->{'name'} = 'topcontainer';
    $top->{'done'} = 1;
    foreach my $i (@_) {
	push @{$top->{'children'}}, { name => $i, parent => $top };
    }
    $self->do_primaries($top, @_);
}

sub do_primaries {
    my $self = shift;
    $self->{'active'} = shift;
    my ($name, $namefull, @pris, @errors);

    my %error_primaries=
      ('noprimary' => 
       {
	'questions' =>
	[ { type => 'table',
	    error => 'Server Error.',
	    text => 'The following QWizard components were missing:',
	    values => [ sub {
			    return [\@errors];
			} ],
	  },
	  { type => 'hidden',
	    name => 'wiz_canceled',
	    values => 1 },
	],
       }
      );

    $self->start_page();
    $self->ask_questions();
}

sub has_actions {
    my $self = shift;
    my $has_actions = 0;
    $self->foreach_primary($self->{'active'},
			   sub { my $pdesc = $_[0];
				 my $p = $_[1]->get_primary($pdesc->{'name'});
				 if (exists($p->{'actions'})) {
				     ${$_[2]} = 1;
				 }
			     }, $self, \$has_actions);
    return $has_actions;
}

sub has_actions_or_post_answers {
    my $self = shift;
    my $has_stuff = 0;
    $self->foreach_primary($self->{'active'},
			   sub { my $pdesc = $_[0];
				 my $p = $_[1]->get_primary($pdesc->{'name'});
				 if (exists($p->{'actions'}) ||
				     exists($p->{'post_answers'})) {
				     ${$_[2]} = 1;
				 }
			     }, $self, \$has_stuff);
    return $has_stuff;
}

sub keep_working {
  my ($self, @otherwise) = @_;
  if ($self->{'generator'}{'keep_working_hook'}) {
      $self->{'generator'}{'keep_working_hook'}->($self->{'generator'});
  }
  my $str = $self->qwparam('qwizard_tree');
  $self->{'active'} = $self->decode_todo_list(\$str);

  # do stuff from the last run that needs doing, like messing with
  # variables that HTML doesn't deal with properly (checkbox off
  # values, etc).
  my $num = 0;
  qwdebug("munging input data as needed and counting last run");
  $self->foreach_primary($self->{'active'},
			 sub {
			     my $num = $_[1];
			     if ($_[0]{'done'} == 2) {
				 $$num++;
				 $_[2]->munge_form_data($_[2]->get_primary($_[0]{'name'}));
				 qwdebug("munging form data for primary $_[0]->{name}");
                             }
                         }, \$num, $self);
  qwdebug("$num primaries ran last time\n");

  $self->start_page();

  qwdebug("checking previous results for errors");
  if (qwparam('redo_screen') || !($self->check_answers($num))) {
      if (qwparam('redo_screen')) {
	  qwdebug("tree clicked, redoing last screen");
      } else {
	  qwdebug("errors found, redoing last screen");
      }

      # mark as undone again
      $self->foreach_primary($self->{'active'},
			     sub {
				 $_[0]{'done'} = 0 if ($_[0]{'done'} == 2);
			     });
  } else {
      if ($num > 0) {
	  # run post_answers clauses and mark as done
	  qwdebug("Running post answers clauses");
	  $self->foreach_primary($self->{'active'},
		sub {
		    if ($_[0]{'done'} == 2) {
			my ($pdesc, $self) = @_;
		        my $p = $self->get_primary($pdesc->{'name'});
		        my $post_answers = 
		          $p->{'post_answers'};

			# run any post_answers clauses
		        if ($#$post_answers > -1) {
			    # remember context for add_todos calls
			    $self->{'context'} = $pdesc;
		            my $results = 
		              $self->do_list(@$post_answers);
		            qwdebug("results: ",join(",",@$results));
		        }

			# remap if needed
			if ($pdesc->{'remap'}) {
			    my $newvars = 
			      $self->map_primary($p, $pdesc->{'remap'}, '');
			    push @{$self->{'pass_next'}}, @$newvars;
			}

			# mark as finished
		        $_[0]{'done'} = 1;

		    }}, $self);
      }
  }

  qwdebug("processing next primaries on the todo list");

  if ($self->do_primaries($self->{'active'})) {
      # There were no primaries left to process, so display the commit
      # screen or run the actions.
      qwdebug("no screens to display, entering confirmation mode");
      if ($self->qwparam('no_actions') || !$self->has_actions() ||
	  !$self->confirm_or_run_actions()) {

	  # cancel button hit, restart at top
	  $self->reset_qwizard();
	  $self->{'state'} = $states{'CANCELED'};
      }
  } else {
      $self->{'state'} = $states{'ASKING'};
  }

  #
  # Handle any auto-updating that's required.
  #
  my $aupd = qwpref('updateflag');
  if($aupd > 0)
  {
# warn "keep_working:  aupd:  $aupd > 0\n";
	my $tempus = qwparam('upd_time');

	#
	# If the time was set to zero, we're assuming it's a manual pause
	# and we won't do anything.
	#
	if($tempus > 0)
	{
# warn "keep_working:  calling do_autoupd($tempus)\n";
		$self->{'generator'}->do_autoupd($tempus);
		$self->add_todos('basic_monitor_table');
	}
  }

}

# Modifies values to change them when not supported via a generator.
# I.e., when a HTML checkbox is off, we set the value to the "off" value
# even though HTML doesn't return one.
sub munge_form_data {
    my ($self, $p) = @_;
    foreach my $q (@{$p->{'questions'}}) {
	if (ref($q) eq "HASH") {
	    if ($q->{'type'} eq "checkbox" &&
		$q->{values} && $#{$q->{values}} > 0) {
		if (!$self->qwparam($q->{'name'})) {
		    my $vals = $self->get_values($q->{values});
		    $vals = [1,0] if ($#$vals == -1);
		    $self->qwparam($q->{'name'}, $vals->[1]);
		}
	    } elsif ($q->{'type'} eq 'button') {
		# remap from the values clause which was the text to
		# the default clause which is the expected value.
		my $vals = $self->get_value($q->{values});
		if ($self->qwparam($q->{'name'}) eq $vals) {
		    $self->qwparam($q->{'name'},
				   $self->get_value($q->{'default'}));
		}
	    }
	}
    }
}

sub check_answers {
    my ($self, $num) = @_;
    my $ret = 1;

    if ($num > 0) {
	$self->foreach_primary($self->{'active'},
	    sub {
		my $pdesc = $_[0];
		return if ($pdesc->{'done'} != 2);
		my $p = $_[1]->get_primary($pdesc->{'name'});
		my $ret = $_[2];
		qwdebug("checking results in " . ($p->{'name'}||$p->{'title'}));
		if ($p->{'check_value'}) {
		    qwdebug("checking primary's check_value func");
		    my @args;
		    my $code;
		    if (ref($p->{check_value}) eq "CODE") {
			$code = $p->{check_value};
		    } elsif (ref($p->{check_value}) eq "ARRAY") {
			$code = $p->{check_value}[0];
			@args = @{$p->{check_value}}[1..$#{$p->{check_value}}];
		    }
		    my $err = $code->($self, $p, @args);
		    if ($err) {
			qwdebug("Error found in primary check_value: $err");
			$pdesc->{'errcount'}++;
			$$ret = 0;
			$pdesc->{'error'} = $err;
		    }
		}
		foreach my $q (@{$p->{'questions'}}) {
		    if (ref($q) eq 'HASH' && $q->{check_value}) {
			my @args;
			my $code;
			if ($q->{'doif'} && ! $q->{'doif'}->($q, $self, $p)) {
			    next;
			}
			if (ref($q->{check_value}) eq "CODE") {
			    $code = $q->{check_value};
			} elsif (ref($q->{check_value}) eq "ARRAY") {
			    $code = $q->{check_value}[0];
			    @args = @{$q->{check_value}}[1..$#{$q->{check_value}}];
			}
			my $err = $code->($self, $q, $p, @args);
			if ($err && $err ne 'OK') {
			    my $name = $q->{'name'};
			    qwdebug("Error found in question $name: $err");
			    $pdesc->{'errcount'}++;
			    $$ret = 0;
			    $pdesc->{'qerrs'}{$q->{'name'}} = $err;
			}
		    }
		}
	    },
	    $self, \$ret);
    }
    return $ret;
}

sub add_todos {
    my $self = shift;
    my $order = '-early';
    my $merge = 0;
    my $remap = $self->{'remap'};
    my $addto = $self->{'context'};
    my $actionslast = 0;
    my $count = 0;

    $remap .= $addto->{'remap'} if ($addto->{'remap'});

    while ($_[0] =~ /^-/) {
	my $arg = shift;
	$order = $arg if ($arg eq '-early');
	$order = $arg if ($arg eq '-late');
	$merge = 1 if ($arg eq '-merge');
	$actionslast = 1 if ($arg eq '-actionslast');
	$remap .= shift if ($arg eq '-remap');
    }

    foreach my $it (reverse @_) {
	$count++;
	my $newchild = {};
	$newchild->{'name'} = $it;
	$newchild->{'parent'} = $addto;
	$newchild->{'remap'} = $remap if ($remap);
	$newchild->{'actionslast'} = 1 if ($actionslast);
	if ($order eq '-early') {
	    # XXX: note that this may mess up action ordering.  This
	    # should go just before the last *done* clause?
	    qwdebug("Adding (early) $it to todos");
	    unshift @{$addto->{'children'}}, $newchild;
	} else {
	    qwdebug("Adding (late) $it to todos");
	    push @{$addto->{'children'}}, $newchild;
	}
    }
    if ($#_ > -1 && $merge) {
	if ($order eq '-early') {
	    $addto->{'children'}[0]{'merge'} = $count;
	} else {
	    $addto->{'children'}[$#{$addto->{'children'}}]{'merge'} = $count;
	}
    }
}

# Takes a list of "stuff" and executes it.  code snippets returns
# errors, and strings may be include directly in the list which will
# be returned as comments/output to the user
sub do_list {
    my $self = shift;
    my @ret;
    foreach my $action (@_) {
	my $result;
	if (ref($action) eq 'CODE') {
	    $result = $action->($self);
	} elsif (ref($action) eq 'ARRAY') {
	    my @a = @{$action};
	    my $it = shift @a;
	    die "fatal spec error.  not an action..." if (ref($it) ne 'CODE');
	    $result = $it->($self, @a);
	} else {
	    $result = "msg:" . $action;
	    $result =~ s/\@([^\@]+)\@/$self->qwparam($1)/eg;
	}
	if (defined($result)) {
	    $result = [$result] if (ref($result) ne 'ARRAY');
	    foreach my $r (@$result) {
		if ($r =~ s/^msg://i) {
		    push @ret, $r;
		} elsif ($r ne "OK") {
		    push @ret, "Error: " . $r;
		}
	    }
	}
    }
    return \@ret;
}

sub do_actions {
    my ($self) = @_;
    $self->{'generator'}->start_actions($self);
    qwdebug("actions: ", Dumper($self->{'active'}));
    $self->do_primary_actions($self->{'active'}, 0);
    $self->{'generator'}->end_actions($self);
}

sub do_action_conform {
    my ($self) = @_;
    $self->{'generator'}->start_confirm($self);
    $self->do_primary_actions($self->{'active'}, 1);
    $self->pass_vars();
    $self->{generator}->do_hidden($self, 'qwizard_tree',
				  $self->qwparam('qwizard_tree'));
    $self->{'generator'}->end_confirm($self);
}

sub do_primary_action_list {
    my ($self, $pdesc, $confirmonly) = @_;
    my $results;

    my $p = $self->get_primary($pdesc->{'name'});
    return if (!$p);

    qwdebug("running actions for $p->{name} for confirm=$confirmonly\n");
    $self->maybe_start_remap($pdesc->{'remap'}, $p);
    if ($confirmonly) {
	if (exists($p->{'actions_descr'})) {
	    foreach my $desc (@{$p->{'actions_descr'}}) {
		if (ref($desc) eq 'CODE') {
		    $desc = $desc->($self);
		}
		if ($desc && $desc ne 'OK') {
		    $self->{'generator'}->do_confirm_message($self,
							     $self->unparamstr($desc));
		}
	    }
	}
    } else {
	if (exists($p->{'actions'})) {
	    $results = $self->do_list(@{$p->{'actions'}});
	    foreach my $r (@$results) {
		next if ($r eq 'OK');
		if ($r =~ /Error: (.*)/) {
		    # XXX: revert entire DB transaction.
		    qwdebug("  ERROR: $1");
		    $self->{'generator'}->do_action_error($self, $1);
		} else {
		    $self->{'generator'}->do_action_output($self, $r);
		}
	    }
	}
    }
    $self->maybe_end_remap($pdesc->{'remap'}, $p);
}

sub do_primary_actions {
    my ($self, $top, $confirmonly) = @_;
    my ($i, $c);

    # first run all the runfirst marked children, back to front
    for($i = $#{$top->{'children'}}; $i > -1; $i--) {
	$c = $top->{'children'}[$i];
	if (!$c->{'actionslast'}) {
	    $self->do_primary_actions($c, $confirmonly);
	}
    }

    $self->do_primary_action_list($top, $confirmonly);

    # then run the child actions which are to be run last.
    for($i = $#{$top->{'children'}}; $i > -1; $i--) {
	$c = $top->{'children'}[$i];
	if ($c->{'actionslast'}) {
	    $self->do_primary_actions($c, $confirmonly);
	}
    }
}

# returns 1 if a primary with a given name was ever run.
# useful in action sequences to determine if something was done
sub primary_was_run {
    my ($self, $name) = @_;
    my $run = 0;
    $self->foreach_primary($self->{'active'},
			 sub {
			     my $run = $_[2];
			     $$run++ if ($_[0]->{name} eq $_[1]);
			 });
    return 1 if ($run);
    return 0;
}

sub confirm_or_run_actions {
    my ($self) = @_;
    $self->start_page();
    if ($self->qwparam('wiz_confirmed') || $self->{no_confirm} ||
	$self->qwparam('no_confirm')) {
	$self->{'state'} = $states{'ACTING'};

	if (ref($self->{'begin_section_hook'}) eq "CODE") {
	    qwdebug("found begin_section_hook. running.");
	    $self->{'begin_section_hook'}($self);
	}

	qwdebug("Confirmation given (or not needed).  Running actions.");
	$self->do_actions();

	#
	# Call the end_section_hook to close off the HTML table in the
	# Commit.  This is needed to let Netscape properly display the
	# post-Commit page.
	#
	if (ref($self->{'end_section_hook'}) eq "CODE") {
	    qwdebug("found end_section_hook. running.");
	    $self->{'end_section_hook'}($self);
	}

	# Reset and start over.
	$self->reset_qwizard();
    } elsif ($self->qwparam('wiz_canceled')) {
	qwdebug("user hit the cancel button");

	# Reset and start over.
	$self->reset_qwizard();
	$self->{'state'} = $states{'CANCELED'};
	return 0;
    } else {

	$self->{'state'} = $states{'CONFIRMING'};
	qwdebug("Displaying confirmation page");
	if (ref($self->{'begin_section_hook'}) eq "CODE") {
	    qwdebug("found begin_section_hook. running.");
	    $self->{'begin_section_hook'}($self);
	}

	$self->do_action_conform();

	if (ref($self->{'end_section_hook'}) eq "CODE") {
	    qwdebug("found end_section_hook. running.");
	    $self->{'end_section_hook'}($self);
	}
    }

    return 1;
}

sub reset_qwizard {
    my $self = shift;
    $self->{'last_screen'} = 1;
    $self->{'generator'}->clear_params();
    $self->{'state'} = $states{'FINISHED'};
}

sub save_queue {
    my ($self, $queue, $name) = @_;
    $name = "wizard_queue_list" if (!$name);
    my $str = join(",",@$queue);
    $self->{generator}->do_hidden($self, $name, $str);
    qwdebug("saving queue: $name  (value=$str)");
    return 1;
}

sub pass_queue {
    my ($self, $name) = @_;
    $self->{generator}->do_hidden($self, ($name || 'wizard_queue_list'),
				  qwparam($name));
}

sub get_queue {
    my ($self, $name) = @_;
    my @queue_list = split(/,/,$self->qwparam($name || "wizard_queue_list"));
    return \@queue_list;
}

# adds a list of hidden tags to be passed along next time.
sub add_and_pass_vars {
    my $self = shift;

    my $newvars = $self->add_vars(@_);
    $self->pass_vars($newvars);
}

sub add_vars {
    my $self = shift;
    my $newvars = shift;

    # already in a form entry, just add them to the list for next time;
    foreach my $i (@_) {
	$newvars->{$i} = 1;
    }
    return $newvars;
}

# passes known list of hidden tags.
sub pass_vars {
    my $self = shift;
    my $vars = $self->qwparam('pass_vars');
    my $newvars = shift;

    qwdebug("vars to process: $vars");
    if (defined($vars)) {
	foreach my $i (split(/,/,$vars), @{$self->{pass_next}}) {
	    next if ($newvars->{$i}); # already handled
	    $newvars->{$i} = 1;
	    qwdebug("passing on: $i -> ", qwparam($i));
	    $self->{'generator'}->do_pass($self, $i);
	}
    }

    qwdebug("passing on pass_vars: ", join(",",keys(%$newvars)));
    my @pass_next = ($self && ref($self->{pass_next}) eq "ARRAY") ? 
      @{$self->{pass_next}} : ();

    $self->{'generator'}->do_hidden($self,
				    'pass_vars', join(",",keys(%$newvars),
				    @pass_next));
}

# returns a list of values based on an array of values, code, and
# arrays containing code and parameters.
sub get_values {
  my ($self, $vals, $norecurs) = @_;
  my @values;
  return [] if (!defined($vals));
  if (ref($vals) eq "ARRAY") {
    if (ref($vals->[0]) eq "CODE") {
      my $cd = shift @$vals;
      if ($norecurs) {
	  push @values, @{$cd->($self, @$vals)};
      } else {
	  push @values, @{$self->get_values($cd->($self, @$vals))};
      }
      unshift @$vals, $cd;  # we must leave $vals as we found it.
    } else {
      if ($norecurs) {
	  push @values, @$vals;
      } else {
	  map { push @values, @{$self->get_values($_)} } @$vals;
      }
    }
  } elsif (ref($vals) eq "CODE") {
      if ($norecurs) {
	  push @values, @{$vals->($self)};
      } else {
	  push @values, @{$self->get_values($vals->($self))};
      }
  } elsif (ref($vals) eq 'HASH') {
    @values = ($vals);
  } elsif (ref($vals) eq "") {
    $vals =~ s/\@([^\@]+)\@/$self->qwparam($1)/eg;
    @values = ($vals);
  }
  return \@values;
}

# same as get_values, but truncates return list to a single value.
sub get_value {
  my ($self, $vals, $norecurse) = @_;
  return ${$self->get_values($vals, $norecurse)}[0];
}

sub get_values_from_labels {
    my ($self, $labels) = @_;
    my ($vals, $i);
    if (ref($labels) eq 'HASH') {
	@$vals = keys(%$labels);
    } elsif (ref($labels) eq 'ARRAY') {
	for($i = 0; $i <= $#$labels; $i += 2) {
	    push @$vals, $labels->[$i];
	}
    }
    return $vals;
}

sub get_labels {
    my ($self, $q) = @_;
    my $labels;
    if (ref($q->{labels}) eq "HASH") {
	%$labels = %{$q->{labels}};
    } else {
	%$labels = @{$self->get_values($q->{'labels'})} if ($q->{'labels'});
    }

    return $labels;
}

sub get_values_and_labels {
    my ($self, $q, $pad) = @_;
    $pad = "" if (!$pad);
    my ($vals, $labels);
    if (exists($q->{values})) {
	$vals = $self->get_values($q->{'values'});
	if (ref($q->{labels}) eq "HASH") {
	    %$labels = %{$q->{labels}};
	} else {
	    %$labels = @{$self->get_values($q->{'labels'})} if ($q->{'labels'});
	}
	# create a label if one doesn't exist
	foreach my $v (@$vals) {
	    $labels->{$v} = $v if (!exists($labels->{$v}));
	}
    } else {
	# no values, generate them from the labels
	if (ref($q->{labels}) eq "HASH") {
	    $vals = [keys(%{$q->{labels}})];
	    %{$labels} = %{$q->{labels}};
	} else {
	    my $labs = $self->get_values($q->{'labels'});
	    %$labels = @$labs;
	    $vals = $self->get_values_from_labels($labs);
	}
    }
    if ($pad ne "") {
	# prepend any specified padding for spacing reasons
	map { $labels->{$_} = $pad . $labels->{$_} } keys(%$labels);
    }
    return ($vals, $labels);
}

sub make_help_link {
    my ($self, $p, $qcount, $text) = @_;
    my $top = $self->{top_location};
    $top .= (($top =~ /\?/) ? "&" : "?");
    $top .= 
      "disp_help_p=$p->{module_name}&disp_q_num=$qcount";
    return "<a target=\"helpwin\" onClick=\"window.open('$top','helpwin','width=500,height=300,toolbar=0,status=1')\" href=\"$top\">";
}

# collects data
sub ask_questions {
    my ($self) = @_;
    my (@passvars, %results, $submods, $count);
    my $repeat = 1;
    $self->{'passvars'} = \@passvars;  # ugly hack for multi-checkboxes
    my $newvars = {};

    $self->{'allqcount'} = 0;

    # count outstanding errors
    $self->{'errs'} = 0;
    $self->foreach_primary($self->{'active'},
			   sub {
			       if ($_[0]->{'errcount'}) {
				   $_[1]->{'errs'} += $_[0]->{'errcount'};
				   qwdebug("primary $_[0]{name} has ", 
					   $_[0]->{'errcount'}, " errors");
				   delete $_[0]->{'errcount'};
			       }
			   }, $self);

    # process each primary we should be processing
    while (my $pdesc = $self->get_next_primary()) {
	my $p = $self->get_primary($pdesc->{'name'});
	$repeat += $pdesc->{'merge'} - 1 if ($pdesc->{'merge'});

	if (ref($p) ne "HASH") {
	    qwdebug("ERROR: primary $pdesc->{'name'} does not exist\n");
	    # XXX: not portable error code
	    print "QWizard Error.  called on $pdesc->{name} which doesn't exist";
	    return 0;
	}

	qwdebug("Processing Primary (more=$repeat): " . 
		($p->{name} || $p->{title})); 
	if ($p->{'take_over'}) {
	    qwdebug("Passing control to primary, take_over hook found"); 
	    $p->{'take_over'}($self, $p);
	    return 0;
	} else {
	    if (!$count) {
		if (ref($self->{'begin_section_hook'}) eq "CODE") {
		    qwdebug("found begin_section_hook. running.");
		    $self->{'begin_section_hook'}($self, $p);
		}
	    }
	}
	if (exists($p->{'setup'})) {
	    qwdebug("primary setup function found.  Running.");
	    delete $p->{'runstate'} if (exists($p->{'runstate'}));
	    my $res = $p->{'setup'}($self, $p);
	    if ($res ne "OK" && $res ne "") {
		qwdebug("primary's setup returned an error: $res");
		$self->{'generator'}->do_error('', $self, $p, $res);
		return 0;
	    }
	}
	$count++;
	if ($p->{'questions'}) {
	  $self->{'qcount'} = -1;
	  qwdebug("starting queston processing/display");
	  $self->{'generator'}->start_questions($self, $p,
						$self->unparamstr($self->get_value($p->{title})),
						(qwpref('pref_intro') ne '0' ? $self->unparamstr($self->get_value($p->{introduction})) : ""));
	  my @questions = @{$p->{'questions'}};
	  my ($q, @newqs);

	  # generate dynamic questions
	  foreach $q (@questions) {
	      if (ref($q) ne "HASH") {
		  push @newqs, $q;
	      } elsif ($q->{type} eq 'dynamic') {
		  qwdebug("Expanding a dynamic");
		  if ($q->{'doif'} && ! $q->{'doif'}->($q, $self, $p)) {
		      qwdebug("Dynamic question skipped");
		      next;
		  }
		  #		  my $v = $self->get_values($q->{values});
		  push @newqs, @{$self->get_values($q->{values})};
	      } else {
		  push @newqs, $q;
	      }
	  }
	  if ($pdesc->{'error'}) {
	      $self->{'generator'}->do_error('', $self, $p, $pdesc->{'error'});
	      delete $pdesc->{'error'};
	  }
	  foreach $q (@newqs) {
	      $self->{'qcount'}++;
	      $self->{'allqcount'}++;
	      $self->{'currentq'} = $q; # for generators mostly
	      $self->{'currentp'} = $p; # for generators mostly
	      push @passvars, $self->ask_question($p, $q);
	  }
	  $self->{'generator'}->end_questions($self, $p);
        }

	if ($p->{'sub_modules'}) {
	  qwdebug("Adding submodules to todo list: $p->{sub_modules}"); 
	  my $vals = $self->get_values($p->{'sub_modules'});
	  if ($#$vals > -1) {
	    map {
		if (!exists($self->{primaries}{$_})) {
		    print STDERR "ERROR: Reference to no such primary: $_\n";
		    # XXX: error to console!
		} else {
		    $self->add_todos($_);
		    qwdebug("  adding: $_");
		}
	    } @$vals;
	  }
	}
	if (exists($p->{'add_vars'})) {
	    # XXX: this doesn't do remapping of these names properly.
	    $newvars = $self->add_vars($newvars, @{$p->{'add_vars'}});
	}
	$repeat--;
	$pdesc->{'done'} = 2;
	if ($repeat <= 0) {
	    qwdebug("Done processing screen's primaries ");
	    if ($self->{'allqcount'}) {
		qwdebug("Done with questions...  Getting user input\n");

		# save current vars list.
		$newvars = $self->add_and_pass_vars($newvars, @passvars);

		# save the call tree
		my $treestr = $self->encode_todo_list();
		$self->{generator}->do_hidden($self, 'qwizard_tree', $treestr);
		qwdebug("saving qwizard tree: $treestr");

		# call the generator's wait_for routine to wrap up.
		my $next = (qwparam('no_actions') ne '' || !$self->has_actions_or_post_answers()) ? 'Finished' : 'Next';
		if (qwparam('no_actions') ne '' || !$self->has_actions_or_post_answers()) {
		    $self->{'last_screen'} = 1;
		}
		$next = qwparam('QWizard_next') if (qwparam('QWizard_next'));
		if ($self->{'generator'}->wait_for($self, $next, $p)) {
		    if (ref($self->{'end_section_hook'}) eq "CODE") {
			qwdebug("end_section_hook found.  Calling.\n");
			$self->{'end_section_hook'}($self, $p);
		    }
		    $self->reset_qwizard() if ($self->{'last_screen'});
		    return 0;
		}
		$self->reset_QWizard() if ($self->{'last_screen'});
	    } else {
		# no questions generated by current screen, try one more.
		$repeat++;
	    }
	}
    }
    return 1;
}

sub ask_question {
    my ($self, $p, $q) = @_;

    my $pdesc = $self->{'context'};

    if (ref($q) ne "HASH") {
	$self->{'generator'}->do_separator($q, $self, $p, $q);
    } else {
	qwdebug("Processing Question: " . 
		sprintf("%-10s %s", ($q->{type} || "text"),
			"$q->{name}")); 
	if ($q->{'doif'} && ! $q->{'doif'}->($q, $self, $p)) {
	    qwdebug("Question skipped");
	    $self->{'qcount'}--;
	    $self->{'allqcount'}++;
	    return;
	}

	# determine the default value.  this is either pulled from the
	# question default clause or from the last value entered from
	# the user if an error occurred and we're redisplaying the
	# question (or repeating it for a tree).
	my $def;
	if ($self->{'errs'} || $self->qwparam('redo_screen')) {
	    $def = $self->qwparam($q->{'name'});
	    qwdebug("  pulling original: $def\n");
	} else {
	    if (qwparam($q->{'name'}) &&
		!$q->{'override'} && !$self->{'override'}) {
		print STDERR "*** QWizard: Warning redefining value from question named $q->{name} (value was: " . qwparam($q->{'name'}) . ".  This may or may not have been intentional.  Add the 'override' flag to the second question, or rename the parent's question, to turn off this warning in the future\n";
	    }
	    $def = $self->get_value($q->{default});
	}

	# display the error
	if (exists($pdesc->{'qerrs'}{$q->{'name'}})) {
	    $self->{'generator'}->do_error($q, $self, $p,
					   $pdesc->{'qerrs'}{$q->{'name'}});
	    delete $pdesc->{'qerrs'}{$q->{'name'}};
	}

	# have the generator display the question text
	$self->{'generator'}->do_question($q, $self, $p, 
					  $self->unparamstr($self->get_value($q->{text})),
					  $self->{'qcount'});

	# have the generator display the question widget based on the type
	my $typemap =
	  $self->{'generator'}->get_handler($q->{'type'} || 'text',$q);
	if ($typemap) {
	    # The generator supplied its own function and what it
	    # wants to receive argument-wise.
	    my $arguments =
	      $self->{'generator'}->get_arguments($self, $q,
						  $typemap->{'argdef'}, $def);
	    $typemap->{'function'}->($self->{'generator'}, $q, $self, $p, 
				     @$arguments);
	} elsif ($q->{type} eq "hidden") {
	    $self->{'generator'}->do_hidden($self, $q->{'name'},
					    $def || $self->get_value($q->{values}));
	    if ($q->{text}) {
		$self->{'generator'}->do_label($q, $self, $p,
					       [$q->{text}],
					       $def);
	    }
	} elsif ($q->{type} eq "raw") {
	    print $self->get_value($q->{values}, $def);
	} elsif ($q->{type} eq "tree") {
	    $self->{'generator'}->do_tree($q, $self, $p,
					  $self->get_labels($q));
	} else {
	    my $typemap =
	      $self->{'generator'}->get_handler('unknown',$q);
	    if ($typemap) {
		# The generator supplied its own error handling function
		my $arguments =
		  $self->{'generator'}->get_arguments($self, $q,
						      $typemap->{'argdef'},
						      $def);
		$typemap->{'function'}->($self->{'generator'}, $q, $self, $p, 
					 @$arguments);
	    } else {
		print STDERR "Unsupported question type ($q->{type})\n";
	    }
	    qwdebug("Unsupported question type ($q->{type})");
	    qwdebug(Dumper($q));
	    return;
	}
	# return the name
	$self->{'generator'}->do_question_end($q, $self, $p, $self->{'qcount'});
	return $q->{'name'};
    }
}

sub display_help {
    my $self = shift;
    $self->start_page();
    my $p = $self->{'primaries'}{$self->qwparam('disp_help_p')};
    if (!$p) {
	print "<h1>No help available</h1>","\n";
	print STDERR "illegal help requested for non-existent primary: " .
	  $self->qwparam('disp_help_p') . "\n";
	return;
    }
    my $q = $p->{'questions'}[$self->qwparam('disp_q_num')];
    if (!$q) {
	print "<h1>No help available</h1>","\n";
	print STDERR "illegal help requested for non-existent question #" . 
	  $self->qwparam('disp_q_num') . " in primary: " . $self->qwparam('disp_help_p') . "\n";
	return;
    }

    if ($q->{text}) {
	print "<h1>Help information for $q->{text}</h1>";
    } else {
	print "<h1>Help text</h1>";
    }
    print "<p>\n";
    if ($q->{helptext}) {
	print "<table width=450><tr><td>\n";
	print "$q->{helptext}\n";
	print "</td></tr></table>\n";
    } else {
	print "none available!\n";
	print STDERR "no help available for question #" . 
	  $self->qwparam('disp_q_num') . " in primary: " . $self->qwparam('disp_help_p') . "\n";
    }
}

sub unparamstr {
  my ($self, $str) = @_;
  $str =~ s/\@([^\@]+)\@/qwparam($1)/eg;
  return $str;
}

sub start_page {
  my $self = shift;
  $qwcurrent = $self;
  qwdebug("starting page");
  $self->{'generator'}->init_screen($self, 
				    $self->{'generator'}->{'title'} ||
				    $self->{'title'} ||
				    'the wizard');
}

sub qwparam {
    my $it = shift;
    my $self;
    if (ref($it) eq "QWizard") {
	$self = $it;
	$it = shift;
    } else {
	$self = $qwcurrent;
    }

    my $generator = $self->{'generator'};

    if (!$generator) {
	print STDERR "QWizard::qwparam:  no generator\n";
	print STDERR "error at qwparam:",join(",",caller(1)),"\n";

	return("");
    }

    return $generator->qwparam($it, @_);
}

sub qw_upload_fh {
    my $it = shift;
    my $self;
    if (ref($it) eq "QWizard") {
	$self = $it;
	$it = shift;
    } else {
	$self = $qwcurrent;
    }

    my $generator = $self->{'generator'};

    if (!$generator) {
	print STDERR "QWizard::qw_upload_fh:  no generator\n";
	print STDERR "error at qw_upload_fh:",join(",",caller(1)),"\n";

	return("");
    }

    return $generator->qw_upload_fh($it, @_);
}

sub qw_upload_file {
    my $it = shift;
    my $self;
    if (ref($it) eq "QWizard") {
	$self = $it;
	$it = shift;
    } else {
	$self = $qwcurrent;
    }

    my $generator = $self->{'generator'};

    if (!$generator) {
	print STDERR "QWizard::qw_upload_fh:  no generator\n";
	print STDERR "error at qw_upload_fh:",join(",",caller(1)),"\n";

	return("");
    }

    return $generator->qw_upload_file($it, @_);
}

sub qwpref {
    my $it = shift;
    my $self;
    if (ref($it) eq "QWizard") {
	$self = $it;
	$it = shift;
    } else {
	$self = $qwcurrent;
    }
    my $generator = $self->{'generator'};

    if (!$generator) {
	print STDERR "QWizard::qwpref: no generator\n";
	print STDERR "error at qwpref:",join(",",caller(1)),"\n";
	return("");
    }
    return $generator->qwpref($it, @_);
}

#
# De/Encoding of primary decision tree based into ASCII storage strings
# and other primary list manipulation routines.
#
sub encode_todo_list {
    my ($self, $top) = @_;
    $top = $self->{'active'} if (!$top);

    my $name = $top->{'name'};
    # XXX: sub-mark [ , ] , , , and :

    # encode keywords
    foreach my $k (keys(%$top)) {
	next if ($k =~ /^(children|parent|name|qerrs)/);
	$name .= ":$k:$top->{$k}";
    }

    # encode children
    if ($top->{'children'} && $#{$top->{'children'}} > -1) {
	my @cnames;
	foreach my $c (@{$top->{'children'}}) {
	    push @cnames, $self->encode_todo_list($c);
	}
	$name .= "[" . join(",",@cnames) . "]";
    }
    return $name;
}

sub decode_todo_list {
    my ($self, $str) = @_;
    my $top = {};

    $$str =~ s/^([^\]\[:,]+)//;
    $top->{'name'} = $1;

    # decode keywords
    while ($$str && $$str =~ s/^:([^\]\[,:]*):([^\]\[,:]*)//) {
	$top->{$1} = $2;
    }

    if ($$str && $$str !~ /^[\[\],]/) {
	print STDERR "decoding error1: $$str is an illegal string";
	return;
    }

    # decode children
    $top->{'children'} = [];
    if ($$str && $$str =~ s/^\[//) {
	while ($$str && $$str !~ /^\]/) {
	    my $child = $self->decode_todo_list($str);
	    if (!$child) {
		print STDERR "decoding error2: $$str is an illegal string";
		return;
	    }
	    $child->{'parent'} = $top;
	    push @{$top->{'children'}}, $child;
	}
	$$str =~ s/^\]//;
    }

    # delete comma before the next in the list
    $$str =~ s/^,//;

    return $top;
}

sub get_next_primary {
    my ($self, $top) = @_;
    $top = $self->{'active'} if (!$top);

    return $top if (!$top->{'done'});
    if ($top->{'children'}) {
	foreach my $c (@{$top->{'children'}}) {
	    my $it = $self->get_next_primary($c);
	    $self->{'context'} = $it;
	    return $it if ($it);
	}
    }
}

sub foreach_primary {
    my $self = shift;
    my $top = shift;
    my $sub = shift;
    my $c;

    $sub->($top, @_);
    if ($top->{'children'}) {
	for ($c = 0; $c <= $#{$top->{'children'}}; $c++) {
	    if ($c == $#{$top->{'children'}}) {
		$top->{'children'}[$c]{'qw_last_foreach'} = 1;
	    }
	    $self->foreach_primary($top->{'children'}[$c], $sub, @_);
	    if ($c == $#{$top->{'children'}}) {
		delete $top->{'children'}[$c]{'qw_last_foreach'};
	    }
	}
    }
}

#
# remaps variables before processing.
#
sub map_primary {
    my ($self, $p, $to, $from) = @_;
    my @retnames;
    foreach my $q (@{$p->{questions}}) {
	next if (ref($q) ne 'HASH');
	# note: qwparam(from, to) so read this backwards.
	qwparam($to . $q->{name}, qwparam($from . $q->{name}));
	push @retnames, $to . $q->{name};
    }
    foreach my $v (@{$self->get_values($p->{parent_variables}, 1)}) {
	# note: qwparam(from, to) so read this backwards.
	qwparam($to . $v, qwparam($from . $v));
	push @retnames, $to . $v;
    }
	
    return \@retnames;
}

sub drop_remap_prefix {
    my $x = shift;
    if (ref($x) eq 'ARRAY') {
	my @z;
	foreach my $y (@$x) {
	    push @z, drop_remap_prefix($y);
	}
	return \@z;
    } else {
	$x =~ s/^remap:.*://;
    }
    return $x;
}

sub maybe_start_remap {
    my ($self, $remapname, $prim) = @_;
    if ($remapname) {
	# save state
	$self->map_primary($prim, "NETPOLICYSave" . $remapname, '');
	# restore remapped data
	$self->map_primary($prim, '', $remapname);
    }
}

sub maybe_end_remap {
    my ($self, $remapname, $prim) = @_;
    if ($remapname) {
	# resave to mapped data prefix
	$self->map_primary($prim, $remapname, '');
	# restore saved state
	$self->map_primary($prim, '', "NETPOLICYSave" . $remapname);
    }
}


###############################################################################
#
# Debugging routines
#

#-----------------------------------------------------------------------
# Routine:	dump_primaries()
#
# Purpose:	This routine dumps all the primary values.
#		Or something.
#
sub dump_primaries {
    my $self = shift;
    return Dumper($self->{'primaries'});
}

#-----------------------------------------------------------------------
# Routine:	qwsetdebug()
#
# Purpose:	This routine sets the QWizard debugging flag based on the
#		value of the debugging preference.
#
sub qwsetdebug {
    my ($self) = @_;

    my $prefval = $self->qwpref('pref_debug');

    #
    # If the QWizard debugging preference doesn't exist yet (which means the
    # generator has yet to be assigned) then we'll assume debugging should
    # be turned off.  If the debugging preference has been set, we'll get it
    # and set the QWizard global debugging flag to that value.
    #
    if($prefval eq "")
    {
	$qwdebug = 0;
	$self->qwpref('pref_debug','No');
    }
    else
    {
	$qwdebug = $prefval;
	if($prefval != 1)
	{
		$qwdebug = 0;
	}
    }
}

#-----------------------------------------------------------------------
# Routine:	qwisdebugon()
#
# Purpose:	Return the debugging flag.
#
sub qwisdebugon {
    return $qwdebug;
}

#-----------------------------------------------------------------------
# Routine:	qwdebug_set_output()
#
# Purpose:	This routine writes a line of QWizard debugging output to
#		Currently only a scalar variable supported.
#
sub qwdebug_set_output {
    shift if (ref($_[0]) eq 'QWizard');
    $qwvar = $_[0];
}

#-----------------------------------------------------------------------
# Routine:	qwdebug()
#
# Purpose:	This routine writes a line of QWizard debugging output to
#		the browser if the QWizard debugging flag is turned on.
#
sub qwdebug {
    if ($qwdebug) {
	my $count = 0;
	while(1) {
	    $count++;
	    last if ($count > 10);
	    my @caller = caller($count);
	    last if ($caller[3] =~ /magic/);
	}
	my $str = "QWizard:" . "  " x $count;
	$str .= join('',@_);
	$str .= "\n" if ($_[$#_] !~ /\n$/);
	if (ref($qwvar) eq 'SCALAR') {
	    $$qwvar .= $str;
	} else {
	    print STDERR $str;
	}
    }
}


###############################################################################
#
# Useful check_value functions.
#

sub qw_required_field {
    if (!length(qwparam($_[1]->{'name'}))) {
	return "This is a required field:";
    }
}

sub qw_integer {
    return qw_optional_integer(@_) if (qwparam($_[1]->{'name'}) ne '');
    return qw_required_field(@_);
}

sub qw_optional_integer {
    if (length(qwparam($_[1]->{'name'})) > 0 &&
	qwparam($_[1]->{'name'}) !~ /^\d+$/) {
	return "This must be an integer value [I.E., a number]";
    }
}

sub qw_hex {
    return qw_optional_hex(@_) if (qwparam($_[1]->{'name'}) ne '');
    return qw_required_field(@_);
}

sub qw_optional_hex {
    if (qwparam($_[1]->{'name'}) !~ /^[a-fA-F0-9]*$/) {
	return "This must be an hex string value [a-f,0-9]";
    }
    if (length(qwparam($_[1]->{'name'})) % 2) {
	return "Hex string values must have an even length ('ab' is legal, 'abc' is not)";
    }
}

sub qw_check_hex_and_length {
  my ($self, $q, $p, $length) = @_;
  my $err;

  # must be hex
  $err = qw_hex($self, $q, $p);
  if($err) {
    return $err;
  }

  # length
  if (length(qwparam($q->{'name'})) != (2 * $length)) {
    return "Value must be " . $length . " bytes, " .
      "which is " . (2 * $length) . " hex characters.";
  }
}

sub check_range {
    my $val = shift;
    my $acceptmsg = "";
    for(my $i=0; $i <= $#_; $i+=2) {
      qwdebug("checking " . $val . " against rage of " . $_[$i] . " to " .
              $_[$i+1]);
	if ($val >= $_[$i] && $val <= $_[$i+1]) {
	    return;
	}
	$acceptmsg .= "(>= $_[$i] and <= $_[$i+1]) or ";
    }
    $acceptmsg =~ s/ or $//;
    return $acceptmsg;
}

sub qw_check_length_ranges {
    my $wiz = shift;
    my $q = shift;
    my $p = shift;
    my $val = length(qwparam($q->{'name'}));
    my $ret = 0;
    my $acceptmsg = "";
    qwdebug("checking length rages of '" . qwparam($q->{'name'}) . "' len = " .
            $val );
    $acceptmsg = check_range($val, @_);
    if ($acceptmsg) {
	return "Answer is not a valid length.  Acceptable length of answers: $acceptmsg";
    }
    return;
}

sub qw_check_int_ranges {
    my $ret = qw_integer(@_);
    return $ret if ($ret);
    my $wiz = shift;
    my $q = shift;
    my $p = shift;
    my $val = qwparam($q->{'name'});
    $ret = 0;
    my $acceptmsg = "";
    for(my $i=0; $i <= $#_; $i+=2) {
	if ($val >= $_[$i] && $val <= $_[$i+1]) {
	    return;
	}
	$acceptmsg .= "(>= $_[$i] and <= $_[$i+1]) or ";
    }
    $acceptmsg =~ s/ or $//;
    if ($acceptmsg) {
	return "Answer out of range.  Acceptable value ranges: $acceptmsg";
    }
    return;
}

1;

#############################################################################

=pod

=head1 NAME

QWizard - Display a series of questions, get the answers, and act on the
answers.

=head1 SYNOPSIS

  use QWizard;

  my %primaries =
  (
   starting_node =>
   { title => "starting here",
     introduction => "foo bar",
     questions =>
     [{	type => 'text',
       	name => 'mytext',
       	text => 'enter something:',
       	default => "hello world" },
      { type => 'checkbox',
        text => 'yes or no:',
        values => ['yes','no'],
        name => 'mycheck'} ],
     actions => 
     [sub { return [
            "msg: text = " . qwparam('mytext'),
            "msg: checkbox = " . qwparam('mycheck')
            ];}]
    }
   );

  my $qw = new QWizard(primaries => \%primaries,
		       title => "window title");

  $qw->magic('starting_node');

=head1 DESCRIPTION

QWizard displays a list of grouped questions, and retrieves and processes
user-specified answers to the questions.  Multiple question/answer sets may
be displayed before the answers are dealt with.  Once a "commit" action is
taken (instigated by the user), a series of actions is performed to handle
the answers.  The actions are executed in the order required by the QWizard
programmer.

QWizard's real power lies in its inherent ability to keep track of all state
information between one wizard screen and the next, even in normally stateless
transaction environments like HTTP and HTML.  This allows a QWizard programmer
to collect a large body of data with a number of simple displays.  After all
the data has been gathered and verified, then it can be handled as appropriate
(e.g., written to a database, used for system configuration, or used to
generate a graph.)

Current user interfaces that exist are HTML, Tk, and (minimally) ReadLine.
A single QWizard script implementation can make use of any of the output
formats without code modification.  Thus it is extremely easy to write
portable I<wizard> scripts that can be used without modification by both
graphical window environments (Tk) and HTML-based web environments (e.g., CGI
scripts.)

Back-end interfaces (child classes of the I<QWizard::Generator> module) are
responsible for displaying the information to the user.  Currently HTML and
Tk, in that order, are the two output mechanisms that work the best.  Others
are planned, but are not far along in development.  Developing new generator
back-ends is fairly simple and doesn't take a lot of code (assuming the
graphic interface is fairly powerful and contains a widget library.)

QWizard operates by displaying a series of "screens" to the user.  Each screen
is defined in a QWizard construct called a I<primary> that describes the
attributes of a given screen, including the list of I<questions> to be
presented to the user.  Primaries can contain questions, things to do
immediately after the questions are answered (I<post_answers>), and things
to do once the entire series of screens have been answered (I<actions>.)
Other information, such as a title and an introduction, can also be attached
to a primary.

After defining a set of primaries, a new QWizard object must be created.  The
QWizard I<new>() constructor is given a set of options, such as window title
and a reference to a hash table containing the primaries.  (The complete set
of options may be found in the "QWizard new() Options" section.) The question
display and data collection is started by calling the I<magic>() routine of
the new QWizard object.

There are examples distributed with the QWizard module sources that may help
to understand the whole system and what it is capable of.  See the B<examples>
directory of the QWizard source code tree for details.  Also, QWizard was
written mostly due to requirements of the Net-Policy project.  Net-Policy
makes very extensive use of QWizard and is another good place to look for
examples.  In fact, the QWizard CVS code is located inside the Net-Policy CVS
tree.  See http://net-policy.sourceforge.net/ for details on the Net-Policy
project.

=head2 MAGIC() PSEUDO-CODE

A pseudo-code walk-through of the essential results of the I<magic>() routine
above is below.  In a CGI script, for example, the I<magic>() routine will be
called multiple times (once per screen) but the results will be the same in
the end -- it's all taken care of magically ;-).

  ################
  ## WARNING:  pseudo-code describing a process! Not real code!
  ################

  # Loop through each primary and display the primary's questions.
  while(primaries to process) {
      display_primary_questions();
      get_user_input();
      check_results();
      run_primary_post_answers();
  }

  # Displays a "will be doing these things" screen,
  # and has a commit button.
  display_commit_screen();

  # Loop through each primary and run its actions.
  # Note: see action documentation about execution order!
  foreach (primary that was displayed) {
      results = run_primary_actions();
      display(results);
  }

  # If magic() is called again, it restarts from
  # the top primary again.

=head2 QWIZARD NEW() OPTIONS

Options passed to the QWizard new() operator define how the QWizard instance
will behave.  Options are passed in the following manner:

  new QWizard (option => value, ...)

Valid options are:

=over 4

=item title => "document title"

The document title to be printed in the title bar of the window.

=item generator => GENERATOR

GENERATOR is a reference to a valid QWizard generator.
Current generator classes are:

  - QWizard::Generator::Best           (default: picks the best available)
  - QWizard::Generator::HTML
  - QWizard::Generator::Tk
  - QWizard::Generator::ReadLine       (limited in functionality)

The I<QWizard::Generator::Best> generator is used if no specific generator
is specified.  The I<Best> generator will create an HTML generator if used
in a web context (i.e., a CGI script), or else pick the best of the available
other generators (Tk, then ReadLine).

This example forces a Tk generator to be used:

   my $wiz = new QWizard(generator => new QWizard::QWizard::Tk(),
                         # ...
                        );

=item top_location => "webaddress"

This should be the top location of a web page where the questions will be
displayed.  This is needed for "go to top" buttons and the like to work.  This
is not needed if the QWizard-based script is not going to be used in a CGI
or other web-based environment.

=item primaries => \%my_primaries

I<my_primaries> will define the list of questions to be given to the user.
I<my_primaries> just defines the questions, but does not mean the user will
be prompted with each question.  The questions in this series that will be
displayed for the user to answer is determined by the I<magic>() function's
starting arguments, described below.  The format of the I<primaries> hash is
described in the B<Primaries Definition> section below.  The recognized
values in the I<primaries> hash is described in the B<Primaries Options>
section.

=item no_confirm => 1

If set, the final confirmation screen will not be displayed, but instead the
resulting actions will be automatically run.  This can also be achieved inside
the wizard tokens primaries by setting a question name to I<no_confirm> with
a value of 1 (using a hidden question type.)

=item begin_section_hook => \&subroutine

This function will be called just before a set of questions is displayed.  It
can be used to perform such functions as printing preliminary information and
initializing data.

=item end_section_hook => \&subroutine

This function will be called just after a set of questions is displayed.

=back

=head2 PRIMARIES DEFINITION

The I<primaries> argument of the I<new>() function defines the list of
questions that may be posed to a user.  Each primary in the hash will contain
a list of questions, answers, etc., and are grouped together by a name (the
key in the hash).  Thus, a typical primary set definition would look something
like:

  %my_primaries =
    (
     # The name of the primary.
     'question_set_1' => 
     # its definition
     {
       title => 'My question set',
       questions =>
          # questions are defined in an array of hashes.
          [{type => 'checkbox',
            text => 'Is this fun?',
            name => is_fun,
            default => 1,
            values => [1, 0] },
           {type => 'text',
            text => 'Enter your name:',
            name => 'their_name'}],
       post_answers =>
          # post_answers is a list of things to do immediately after
          # this set of questions has been asked.
          [ sub { print "my question set answered" } ],
       actions =>
          # actions is a list of actions run when all is said and done.
          [ sub {
                  return "msg: %s thinks this %s fun.\n",
                  qwparam('their_name'),
                  (qwparam('is_fun')) ? "is" : "isn't" 
                 }],
       actions_descr =>
          # An array of strings displayed to the user before they agree
          # to commit to their answers.
          [ 'I\'m going to process stuff from @their_name@)' ]
      });

See the I<QWizard::API> module for an alternative, less verbose, form of API
for creating primaries which can produce more compact-looking code.

=head3 VALUE conventions

In the documentation to follow, any time the keyword VALUE appears, the
following types of "values" can be used in its place:

  - "a string"
  - 10
  - \&sub_to_call
  - sub { return "a calculated string or value" }
  - [\&sub_to_call, arguments, to, sub, ...]

Subroutines are called and expected to return a single value or an array
reference of multiple values.

Much of the time the VALUE keyword appears in array brackets: [].  Thus you
may often specify multiple values in various ways.  E.g., a values clause in
a question may be given in this manner:

  sub my_examp1 { return 3; }
  sub my_examp2 { return [$_[0]..$_[1]]; }

  values => [1, 2, \&my_examp1, [\&my_examp2, 4, 10]],

After everything is evaluated, the end result of this (complex) example will
be an array passed of digits from 1 to 10 passed to the values clause.

In any function at any point in time during processing, the I<qwparam>()
function can be called to return the results of a particular question as it
was answered by the user.  I.e., if a question named I<their_name> was
answered with "John Doe" at any point in the past series of wizard screens,
then I<qwparam('their_name')> would return "John Doe".  As most VALUE
functions will be designed to process previous user input, understanding this
is the key to using the QWizard Perl module.  More information and examples
follow in the sections below.

=head2 PRIMARY OPTIONS

These are the tokens that can be specified in a primary:

=over 4

=item title => VALUE

The title name for the set of questions.  This will be displayed at
the top of the screen.

=item introduction => VALUE

Introductory text to be printed above the list of questions for a given
primary.  This is useful as a starting piece of text to help the user with
this particular wizard screen.  Display of the introductory text is controlled
by the Net-Policy I<pref_intro> user preference.  The default is to display
introductory text, but this setting can be turned off and on by the user.

=item questions => [{ QUESTION_DEFINITION }, { QUESTION_DEFINITION }, ...]

This is a list of questions to pose to the user for this screen.

The B<Question Definitions> section describes valid question formatting.

=item post_answers => [ VALUES ]

This is a list of actions to run after the questions on the screen have been
answered.  Although this is a VALUES clause, as described above, these should
normally be subroutines and not hard-coded values.  The first argument to the
VALUE functions will be a reference to the wizard.  This is particularly
useful to conditionally add future screens/primaries that need to be shown
to the user.  This can be done by using the following I<add_todos>() function
call in the I<action> section:

     if (some_condition()) {
         $_[0]->add_todos('primary1', ...);
     }

See the B<QWizard Object Functions> section
for more information on the I<add_todos>() function, but the above
will add the 'primary1' screen to the list of screens to display for the user
before the wizard is finished.

# A post_answers subroutine B<MUST> return the word "OK" for it to be
# successful.  Returning anything else will print the result, as if it
# is an error message, to the user.

For HTML output, these will be run just before the next screen is printed
after the user has submitted the answers back to the web server.  For
window-based output (Tk, etc.) the results are similar and these subroutines
are evaluated before the next window is drawn.

=item actions => [ VALUES ]

The action functions will be run after the entire wizard series of questions
has been displayed and answered and after the user has hit the "commit"
button.  It is assumed that the actions of the earlier screens are dependent
on the actions of the later screens and so the action functions will be
executed in reverse order from the way the screens were displayed.  See the
I<add_todos>() function description in the B<QWizard Object Functions> section
for more information on to change the order of execution away from the default.

The collected values returned from the VALUES evaluation will be displayed
to the user.  Any message beginning with a 'msg:' prefix will be displayed
as a normal output line.  Any value not prefixed with 'msg:' will be displayed
as an error (typically displayed in bold and red by most generators.)

=item actions_descr => [ VALUES ]

Just before the actions are run, a change-summary screen is shown to the user.
A "commit" button will also be given on this screen.  VALUE strings, function
results, etc., will be displayed as a list on this commit screen.  Strings
may have embedded special @TAG@ keywords which will be replaced by the value
for the question with a name of TAG.  These strings should indicate to the
user what the commit button will do for any actions to be run by this set of
questions.  If any question was defined whose name was I<no_confirm> and whose
value was 1, this screen will be skipped and the actions will be run directly.

=item sub_modules => [ 'subname1', ... ]

This hash value adds the specified sub-modules to the list of screens to
display after this one.  This is equivalent to having a I<post_answers> clause
that includes the function:

  sub { $_[0]->add_todos('subname1', ...); }

=item take_over => \&subroutine

This hash value lets a subroutine completely take control of processing
beyond this point.  The wizard methodology functionally stops here and control
for anything in the future is entirely passed to this subroutine.  This should
be rarely (if ever) used and it is really a way of breaking out of the wizard
completely.

=back

=head2 QUESTION DEFINITIONS

Questions are implemented as a collection of hash references.  A question
generally has the following format:

  {
      type => QUESTION_TYPE
      text => QUESTION_TEXT,
      name => NAME_FOR_ANSWER,
      default => VALUE,
      # for menus, checkboxes, multichecks, ... :
      values => [ VALUE1, VALUE2, ... ],                # i.e., [VALUES]
      # for menus, checkboxes, multichecks, ... :
      labels => { value1 => label1, value2 => label2 }  # i.e., [VALUES]
  }

Other than this sort of hash reference, the only other type of question
allowed in the question array is a single "" empty string.  The empty string
acts as a vertical spatial separator, indicating that a space should occur
between the previous question and the next question.

The fields available to question types are given below.  Unless otherwise
stated, the fields are available to all question types.

=over

=item name => 'NAME'

Names the answer to the question.  This name can then be used later in other
sections (I<action>, I<post_answers>, etc.) to retrieve the value of the
answer using the I<qwparam>() function.  For example, I<qwparam>('NAME') at
any point in future executed code should return the value provided by the
user for the question named 'NAME'.

The namespace for these names is shared among all primaries (except 'remapped'
primaries, which are described later).  A warning will be issued if different
questions from two different primaries use the same name.  This warning will
not be given if the question contains an I<override> flag set to 1.

=item text => 'QUESTION TEXT'

Text displayed for the user for the given question.  The text will generally
be on the left of the screen, and the widget the user is supposed to interact
with will be to the question text's right.  (This is subject to the
implementation of the back-end question Generator.  The standard QWizard
generators use this layout scheme.)

=item type => 'TYPE'

Defines the type of question.  TYPE can be one of:

=over 8

=item label

Displays information on the screen without requesting any input.  The text
of the question is printed on the left followed by the values portion on the
right.  If the values portion is omitted, the text portion is printed across
the entire width of the screen.

=item paragraph

Paragraphs are similar to labels but are designed for spaces where
text needs to be wrapped and is likely to be quite long.

=item text

Text input.  Displays an entry box where a standard single line of text can
be entered.

=item textbox

Text input, but in a large box allowing for multi-line entries.

=item hidetext

Obscured text input.  Displays a text entry box, but with the typed text
echoed as asterisks.  This is suitable for prompting users for entering
passwords, as it is not shown on the screen.

=item checkbox

A checkbox.  The I<values> clause should have only 2 values in it: one for
its "on" value, and one for its "off" value (which defaults to 1 and 0,
respectively).

=item multi_checkbox

Multiple checkboxes, one for each label/value pair.  The I<name> question
field is a prefix, and all values and/or label keywords will be the second
half of the name.

For example, the following clauses:

  {
      type => 'multi_checkbox',
      name => 'something',
      values => ['end1','end2'],
      ...
  }

will give parameters of 'somethingend1' and 'somethingend2'.

=item radio

Radio buttons, only one of which can be selected at a time.  If two questions
have the same I<name> and are of type 'radio', they will be "linked" together
such that clicking on a radio button for one question will affect the other.

=item menu

Pull-down menu, where each label is displayed as a menu item.  If just the
I<values> clause (see below) is used, the labels on the screen will match the
values.  If the I<labels> clause is used, the values shown to the user will
be converted to the screen representations that will differ from the
I<qwparam>() values available later.  This is useful for displaying human
representations of programmatic values.  E.g.:

  {
      type => 'menu',
      name => 'mymenu',
      labels => [ 1 => 'my label1',
                  2 => 'my label2']
  }

In this example, the user will see a menu containing 2 entries "my label1"
and "my label2", but I<qwparam>() will return 1 or 2 for I<qwparam('mymenu')>.

=item table

Table to display.  The I<values> section should return a reference to an
array, where each element of the array is a row containing the columns to
display for that row.  The top-most table must actually be returned in an
array itself.  (This is due to an oddity of internal QWizard processing).
E.g.:

  {
      type => 'table',
      text => 'The table:',
      values => sub {
          my $table = [['row1:col1', 'row1:col2'],
                       ['row2:col1', 'row2:col2']];
          return [$table];
        }
  }

This would be displayed graphically on the screen in this manner:

     row1:col1     row1:col2

     row2:col1     row2:col2

Additionally, a column value within the table may itself be a sub-table
(another double-array reference set) or a hash reference, which will be a
sub-widget to display any of the other types listed in this section.

Finally, a I<headers> clause may be added to the question definition
which will add column headers to the table.  E.g.:

  headers => [['col1 header','col2 header']]

=item fileupload

A dialog box for a user to upload a file into the application.  When a user
submits a file the question I<name> can be used later to retrieve a read file
handle on the file using the function I<qw_upload_fh('NAME')>.
I<qwparam('NAME')> will return the name of the file submitted, but because
of the variability in how web-browsers submit file names along with the data,
this field should generally not be used.  Instead, get access to the data
through the I<qw_upload_fh>() function instead.

=item image

Image file.  The image name is specified by the I<image> hash keyword.
Several optional hash keys are recognized to control display of the image.
I<imagealt> specifies a string to display if the image file is not found.
I<height> specifies the height of the image.  I<width> specifies the width
of the image.  (I<height> and I<width> are currently only implemented for
HTML.)

=item graph

Graph of passed data.  This is only available if the I<GD::Graph> module is
installed.  Data is passed in from the I<values> clause and is expected to
be an array of arrays of data, where the first row is the x-axis data, and
the rest are y values (one line will be drawn for each y value).

Additionally, the I<GD::Graph> options can be specified with a
I<graph_options> tag to the question, allowing creation of such things as
axis labels and legends.

=item tree

Hierarchical tree.  Displays a selectable hierarchical tree set from which
the user should pick a single item.  Two references to subroutines must be
passed in via the I<parent> and I<children> question tags.  Also, a I<root>
tag should specify the starting point.

The I<parent> function will be passed a wizard reference and a node name.  It
is expected to return the name of the node's parent.

The I<children> function will be passed a wizard reference and a node name.
It is expected to return an array reference to all the children names.

Both functions should return B<undef> when no parents or children exist above
or below the current node.

=item button

Button widget.  When the button is clicked, the QWizard parameter I<name>
(available by calling I<qwparam('name')>) will be assigned the value indicated
by the I<default> clause.  The parameter value will not be set if the button
is not clicked.  The button's label text will be set to the value of the
I<values> clause.

The button widget will be equivalent to pressing the next button.  The next
primary will be shown after the user presses the button.

=item hidden

This clause is used to set internal parameters (name => value), but these
values are not shown to the user.

B<Note:>  This is not a secure way to hide information from the user.  The
data set using I<hidden> are contained, for example, in the HTML text sent
to the user.

=item dynamic

A dynamic question is one where the I<values> field is evaluated and is
expected to return an array of question definitions which are in turn
each evaluated as a question.  It is useful primarily when doing
things like creating a user-defined number of input fields, or
interacting with an external data source where the number of questions
and their nature is directly related to the external data source.

=item raw

Raw data.  The I<values> portion is displayed straight to the screen.  Use
of this is strongly discouraged.  Obviously, the I<values> portion should be
a subroutine that understands how to interact with the generator.

Really, don't use this.  It's for emergencies only.  It only works with HTML
output.

=back

=item values => [ VALUES ]

An array of values that may be assigned to question types that need choices
(eg: I<menu>, I<checkbox>, I<multi_checkbox>.)  It should be a reference to
an array containing a list of strings, functions to execute, and possibly
sub-arrays containing a function and arguments, as described by the VALUE
conventions section above.  Any function listed in a I<values> clause should
return a list of strings.

The I<values> clause is not needed if the I<labels> clause is present.

=item labels => [ VALUE1 => 'LABEL1', VALUE2 => 'LABEL2', ... ]

Assigns labels to the question's values.  Labels are displayed to the user
instead of the raw values.  This is useful for converting human-readable text
strings into real-world values for use in code.

If the I<values> clause is not specified and the I<labels> clause is, the
values to display are extracted from this I<labels> clause directly.  If a
value from the I<values> clause does not have a corresponding label, the raw
value is presented and used instead.  Generally, only the I<labels> clause
should be used with radio buttons, menus, or check boxes; but either or both
in combination work.

The I<labels> clause subscribes to all the properties of the VALUES convention
previously discussed.  Thus, it may be a function, an array of functions, or
any other type of data that a VALUE may be.  The final results should be an
array, especially if the I<values> clause is not present, as the order
displayed to the user can be specified.  It can also be a hash as well but
the displayed order is subject to Perl I<keys>() conventions and thus an array
is preferred when no I<values> clause has been defined.

=item default => VALUE

The default value to use for this question.  It may be a subroutine
reference which will be called to calculate and return the value.

=item check_value => \&subroutine

A script to check the answer submitted by the user for legality.  It should
return a string if the value submitted was not legal.  The string will be
shown to the user as an error message that the user must fix before being
allowed to proceed further in the wizard screens.  The current primary screen
will be repeated until the function returns no error.

The arguments passed to the function are the reference to the wizard,
a reference to the question definition (the hash), and a reference
to the primary containing the question (also a hash.)  The function
should use the I<qwparam>() function to obtain the value to check.  An
array can be passed in which the first argument should be the
subroutine reference, and the remaining arguments will be passed back
to the subroutine after the already mentioned default arguments.

There are a set of standard functions that can be used for checking
values.  These are:

=over 4

=item \&qw_required_field

Ensures that a value is supplied or else a "This is a required field"
error message is returned.  The function only checks that the value
is non-zero in length.

=item \&qw_integer
=item \&qw_optional_integer

Ensures that the value is an integer value (required or not, respectively.)

=item \&qw_hex
=item \&qw_optional_hex

Ensures that the value is a hex string (required or not, respectively.)

=item [\&qw_check_hex_and_length, length]

Ensures that a value is supplied and is a hex string sufficiently long
for I<length> bytes. This means that the hex string must be "I<length> * 2"
ASCII characters (two hex characters per byte.)

=item [\&qw_check_int_ranges, low1, high1, low2, high2, ...]

Ensures that the value specified falls within one of the I<lowX> -
I<highX> ranges.  The value must be between (I<low1> and I<high1>) or
(I<low2> and I<high2>).

=item [\&qw_check_length_ranges, low1, high1, low2, high2, ...]

I<qw_check_length_ranges> is similar to I<qw_check_int_ranges>(), but it
checks that the length of the data string specified by the user falls within
the given ranges.

=back

=item helptext
=item helpdesc

If specified, these define the help text for a question.  I<helpdescr> should
be short descriptions printed on screen when the wizard screen is displayed,
and I<helptext> should be a full length description of help that will be
displayed only when the user clicks on the help button.  I<helpdescr> is
optional, and a button will be shown linking to I<helptext> regardless.

=back

=head1 SPECIAL VARIABLES

A few QWizard parameters are special and help control how QWizard behaves.
Most of these should be set in the primaries question sets using a hidden
question type.

=over

=item no_actions

If set to 1, the I<actions> phase will not be run.

=item no_confirm

If set to 1, the screen which prompts the user to decide if they really want
to commit their series of answers won't be shown.  Instead, QWizard will jump
straight to the I<actions> execution (if appropriate.)  This can also be given
as a parameter to the QWizard I<new>() function to make it always true.

=item allow_refresh

If the contents of a screen are generated based on data extracted from
dynamically changing sources (e.g., a database), then setting this
parameter to 1 will add a "Refresh" button beside the "Next" button
so that the user can request the screen be redrawn (possibly changing
its contents).

As an example, Net-Policy uses this functionality to allow users to redisplay
generated graphs and maps that will change dynamically as network data are
collected.

This token can also be set directly in a primary definition to affect
just that primary screen.

=item QWizard_next

The button text to display for the "Next" button.  This defaults to
"Next" but can be overridden using this parameter.

=back

=head1 QWIZARD RESERVED VARIABLES

The following parameters are used internally by QWizard.  They should not be
modified.

=over

=item pass_vars

=item qwizard_tree

=item display_help_p

=item disp_q_num

=item redo_screen

=item upd_time

=item wiz_confirmed

=item wiz_canceled

=item wizard_queue_list

=back

=head1 QWizard OBJECT FUNCTIONS

The following functions are defined in the QWizard class and can be called
as needed.

=over

=item $qw->magic(primary_name, ...);

This tells QWizard to start its magic, beginning at the primary named
I<primary_name>.  Multiple primaries will be displayed one after the other
until the list of primaries to display is empty.  The I<actions> clauses of
all these primaries will not be run, however, until after all the primaries
have been processed.

The I<magic>() routine exits only after all the primaries have been run up
through their actions, or unless one of the following conditions occurs:

  - $qw->{'one_pass'} == 1
  - $qw->{'generator'}{'one_pass'} == 1

By default, some of the stateless generators (HTML) will set their I<one_pass>
option automatically since it is expected that the client will exit the
I<magic>() loop and return later with the next set of data to process.  The
I<magic>() routine will automatically restart where it left off if the last
set of primaries being displayed was never finished.  This is common for
stateless generators like HTTP and HTML.

=item $qw->add_todos([options], primary_name, ...);

Adds a primary to the list of screens to display to the user.  This
function should be called during the I<post_answers> section of a primary.
Options that can be passed before the first primary name are:

=over

=item -early

Adds the primaries in question as early as possible in the todo list
(next, unless trumped by future calls.)  This is the default.

=item -late

Adds the primary to the B<end> of the list of primaries to call, such
that it is called last, unless another call to I<add_todos>() appends
something even later.

=item -merge

Merges all the specified primaries listed into a single screen.  This has the
effect of having multiple primaries displayed in one window.

=item -actionslast

All the actions of subsequent primaries that have been added as the result
of a current primary's I<post_answers> clauses are called B<before> the
actions for the current primary.  This means that the I<actions> of any
childrens are executed prior to the I<actions> of their parents.  This is
done by default, as the general usage prediction is that parent primaries are
likely to be dependent on the actions of their children in order for their
own actions to be successful.

However, this flag indicates that the actions of the childrens' primaries
listed in this call are to be called B<before> the current primary's actions.

=item -remap => 'NAME'

If a series of questions must be called repeatedly, you can use this flag to
I<remap> the names of the child primary questions to begin with this prefix.
The children's clauses (I<questions>, I<actions>, I<post_answers>, etc.) will
be called in such a way that they can be oblivious to the fact this is being
done behind their backs, allowing I<qwparam>() to work as expected.  However,
for the current primary (and any parents), the 'NAME' prefix will be added
to the front of any question name values that the child results in defining.

This is rather complex and is better illustrated through an example.  There
is an example that illustrates this in the QWizard Perl module source code
B<examples> directory, in the file B<number_adding.pl>.  This code repeatedly
asks for numbers from the user using the same primary.

=back

=item $qw->add_primary(key => value, key => value);

Adds a primary definition into the existing primary data set for the
QWizard object.  One key value pair B<MUST> be a 'name' => 'NAME'
pair, where NAME will be the installed primary name for later referral
(e.g., in I<add_todos>() calls.)  If a name collision takes place (a
primary already exists under the given name), the original is kept
and the new is not installed.

=item $qw->merge_primaries(\%new_primaries);

Merges a new set of primaries into the existing set.  If a name
collision takes place, the original is kept and the new is not
installed.

=item $qw->get_primary('NAME');

Returns a primary definition given its NAME.

=item $val = $qw->qwparam('NAME')

=item $val = qwparam('NAME')

=item $qw->qwparam('NAME', 'VALUE')

=item qwparam('NAME', 'VALUE')

Retrieves a value specified by NAME that was submitted by a user from a
QWizard widget.  If a VALUE is specified as a second argument, it replaces
the previous value with the new for future calls.

QWizard parameters are accessible until the last screen in which all the
actions are run and the results are displayed.  Parameters are not retained
across primary execution.

The I<qwparam>() function is exported by the QWizard module by default, so
the function shouldn't need to be called directly from the QWizard object.
Thus, just calling I<qwparam('NAME')> by itself will work.

=item $val = $qw->qwpref('NAME')

=item $val = qwpref('NAME')

=item $qw->qwpref('NAME', 'VALUE')

=item qwpref('NAME', 'VALUE')

I<qwpref>() acts almost identically to I<qwparam>(), except that it is
expected to be used for "preferences" -- hence the name.  The preferences are
stored persistently across primary screens, unlike parameters.  Preferences
are not erased between multiple passes through the QWizard screens.  (In the
HTML generator, they are implemented using cookies).

=back

=head1 DEBUGGING

The variable I<$QWizard::qwdebug> controls debugging output from QWizard.  If
set to 1, it dumps processing information to STDERR.  This can be very useful
when debugging QWizard scripts as it displays the step-by-step process about
how QWizard is processing information.

Additionally, a I<qwdebug_set_output>() function exists which can control the
debugging output destination.  Its argument should be a reference to a
variable where the debugging output will be stored.  Thus, debugging
information can be stored to a previously opened error log file by doing the
following:

  our $dvar;
  $QWizard::qwdebug = 1;
  $qw->qwdebug_set_output(\$dvar);
  $qw->magic('stuff');
  print LOGFILE $dvar;

=head1 EXAMPLES

There are a few usage examples in the B<examples> directory of the source
package.  These examples can be run from the command line or installed as a
CGI script without modification.  They will run as a CGI script if run from
a web server, or will launch a Tk window if run from the command line.

=head1 EXPORT

I<qwparam>(), I<qwpref>()

I<qw_required_field>(), I<qw_integer>(), I<qw_optional_integer>(),
I<qw_check_int_ranges>(), I<qw_check_length_ranges>(), I<qw_hex>(),
I<qw_optional_hex>(), I<qw_check_hex_and_length>()

=head1 AUTHOR

Wes Hardaker, hardaker@users.sourceforge.net

=head1 SEE ALSO

perl(1)

Net-Policy: http://net-policy.sourceforge.net/

=cut
