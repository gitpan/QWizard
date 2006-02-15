package QWizard::Plugins::Bookmarks;

our $VERSION = '2.2.3';
require Exporter;

use strict;
use QWizard;
use QWizard::API;
use QWizard::Storage::File;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(init_bookmarks);

our $marks;

our $memory_mark = '__memory_mark';

our @questions =
  (
   { type => 'menu', name => 'qwbookmarks',
     values => \&get_bookmark_list,
     submit => 1,
     default => 'Bookmarks', override => 1},
  );

our %bookmark_primaries =
  (
   get_bookmark_name =>
   { title => 'Define a Bookmark',
     questions =>
     [qw_text('bookmark_name', "Bookmark Name:", 
	      check_value => \&QWizard::qw_required_field)],
   }
  );

sub get_bookmark_list {
    my @list = ('Bookmarks', 'Add page as a bookmark');
    my $all = $marks->get_all();
    push @list, (grep { $_ ne $memory_mark } keys(%$all));
    return \@list;
}

sub bookmarks_start_page_begin {
    my ($qw) = @_;
    return if ($qw->qwpref('qw_nobookmarks'));
    if ($qw->qwparam('qwbookmarks') ne 'Bookmarks') {
	if ($qw->qwparam('qwbookmarks') eq 'Add page as a bookmark') {
	    if (!$qw->qwparam('bookmark_name')) {
		$qw->add_todos('get_bookmark_name');
	    }
	}
    }
}

sub bookmarks_keep_working_begin {
    my ($qw) = @_;

    return if ($qw->qwpref('qw_nobookmarks'));
    if ($qw->qwparam('bookmark_name')) {
	#
	# memorize the page the user was looking at
	#   Note: which is different than where we are now
	#
	my $str = $marks->get($memory_mark);
	$marks->set($qw->qwparam('bookmark_name'), $str);
	# after saving it, reset to that point to continue on
	$qw->{'generator'}{'datastore'}->from_string($str);
    }
    if ($qw->qwparam('qwbookmarks') ne 'Bookmarks') {
	if ($qw->qwparam('qwbookmarks') ne 'Add page as a bookmark') {
	    #
	    # Jump to the requested book mark
	    #
	    my $str = $marks->get($qw->qwparam('qwbookmarks'));
	    $qw->{'generator'}{'datastore'}->from_string($str);
	}
    } else {
	# save the current QWizard history spot for use later if they
	# do bookmark this page.
	my $str = $qw->{'generator'}{'datastore'}->to_string();
	$marks->set($memory_mark, $str);
    }
}

sub init_bookmarks {
    my ($qw, $storage) = @_;
    $marks = $storage;
    push @{$qw->{'topbar'}},@questions;
    $qw->add_hook('start_page_begin', \&bookmarks_start_page_begin);
    $qw->add_hook('keep_working_begin', \&bookmarks_keep_working_begin);
    $qw->merge_primaries(\%bookmark_primaries);
}

=pod

=head1 NAME

QWizard::Plugins::Bookmarks - Adds a bookmark menu to QWizard based applications
answers.

=head1 SYNOPSIS

  use QWizard;
  use QWizard::Storage::File;
  use QWizard::Plugins::Bookmarks;

  my $qw = new QWizard( ... );
  my $storage = new QWizard::Stoarge::File(file => "/path/to/file");
  bookmarks_init($qw, $storage);

=head1 DESCRIPTION

This module simply adds in a menu at the top of all QWizard screens to
create and, display and jump to bookmarks.  The bookmarks_init
function needs access to the already created qwizard object and a
QWizard storage container (SQL or File based ones, for example, work
well).

The bookmarks will not be shown if the qw_nobookmarks preference is
set to a true value.

=head1 AUTHOR

Wes Hardaker, hardaker@users.sourceforge.net

=head1 SEE ALSO

perl(1)

Net-Policy: http://net-policy.sourceforge.net/

=cut

1;
