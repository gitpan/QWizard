package QWizard::Storage::CGIParam;

use strict;

our $VERSION = '2.0.1';
use CGI;

our %cached_params = ();

sub new {
    my $class = shift;
    bless {}, $class;
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
    if (!exists($self->{'cgi'})) {
	# we do this here late binding as possible for various reasons
	$self->{'cgi'} = new CGI;
    }
    if ($#_ > -1) {
	return $cached_params{$it} if (exists($cached_params{$it}));
	$ret = $self->{'cgi'}->param($it, $_[0]);
    } else {
	return $cached_params{$it} if (exists($cached_params{$it}));

	$ret = $self->{'cgi'}->param($it);
    }
    #    print STDERR "qwparam (\"$self\", \"$it\", \"$_[0]\") -> $ret\n";
    return $ret;
}

sub get {
    return access(@_);
}

sub set {
    return access(@_);
}

sub reset {
    %cached_params = ();
}


1;

=pod

=head1 NAME

QWizard::Storage::CGIParam - Stores data in CGI variables

=head1 SYNOPSIS

  my $st = new QWizard::Storage::CGIParam();
  $st->set('var', 'value');
  $st->get('var');

=head1 DESCRIPTION

Stores data passed to it inside of CGI parameters.

=head1 AUTHOR

Wes Hardaker, hardaker@users.sourceforge.net

=head1 SEE ALSO

perl(1)

Net-Policy: http://net-policy.sourceforge.net/

=cut
