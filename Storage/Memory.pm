package QWizard::Storage::Memory;

use strict;

our $VERSION = '2.0.1';
use CGI;

sub new {
    my $class = shift;
    bless {}, $class;
}

sub access {
    my $self = shift;
    my ($it);
    if (ref($self) =~ /QWizard/) {
	$it = shift;
    } else {
	$it = $self;
    }
    if ($#_ > -1) {
	$self->{'vars'}{$it} = $_[0];

    }
#    print "************************************************** $self $it $self->{'vars'}{$it}\n";
    return $self->{'vars'}{$it};
}

sub get {
    return access(@_);
}

sub get_all {
    my $self = shift;
    return $self->{'vars'};
}

sub set_all {
    my $self = shift;
    %{$self->{'vars'}} = %{$_[0]};
}

sub set {
    return access(@_);
}

sub reset {
    my $self = shift;
    %{$self->{'vars'}} = ();
}

1;

=pod

=head1 NAME

QWizard::Storage::Memory - Stores data in CGI variables

=head1 SYNOPSIS

  my $st = new QWizard::Storage::Memory();
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
