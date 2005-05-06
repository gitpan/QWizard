package QWizard::Storage::CGICookie;

use strict;

our %cached_cookies = ();

our $VERSION = '2.1';
use CGI qw(escapeHTML);

sub new {
    my $class = shift;
    my $qw = shift;
    bless {wiz => $qw}, $class;
}

sub access {
    my ($self) = shift;
    my ($it);
    my $ret;
    if (ref($self) =~ /QWizard/) {
	$it = shift;
    } else {
	$it = $self;
    }
    if ($#_ > -1) {
	# security problems with passed in values.  escape them.
	my $str = "\n<script> document.cookie = \"" . escapeHTML($it) . "=" .
	  escapeHTML($_[0]) .
	    "; path=/; expires=Mon, 16-Sep-2013 22:00:00 GMT\"</script>";
	$cached_cookies{$it} = $_[0];
	if ($self->{'started'}) {
	    print $str;
	} else {
	    push @{$self->{'immediate_out'}}, $str;
	}
    } else {
	return $cached_cookies{$it} if (exists($cached_cookies{$it}));
	# XXX: optimize this
	my %cookies = fetch CGI::Cookie;
	return if (!exists($cookies{$it}));
	return $cookies{$it}->value;
    }
    return $ret;
}

sub get {
    return access(@_);
}

sub set {
    return access(@_);
}

sub reset {
    %cached_cookies = ();
}

1;

=pod

=head1 NAME

QWizard::Storage::CGICookie - Stores data in web cookies.  Requires javascript.

=head1 SYNOPSIS

  my $st = new QWizard::Storage::CGICookie();
  $st->set('var', 'value');
  $st->get('var');

=head1 DESCRIPTION

Stores data passed to it inside of web cookies.  It requires
javascript so that the cookies can be set from anywhere including
after the HTTP headers have already been sent.

=head1 AUTHOR

Wes Hardaker, hardaker@users.sourceforge.net

=head1 SEE ALSO

perl(1)

Net-Policy: http://net-policy.sourceforge.net/

=cut
