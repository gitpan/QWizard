package QWizard::Storage::SQL;

use strict;
use QWizard::Storage::Base;

our @ISA = qw(QWizard::Storage::Base);

our $VERSION = '2.2.1';

our %default_opts =
  (
   table => 'QWStorage',
   namecol => 'name',
   valcol => 'value',
  );

sub new {
    my $class = shift;
    my $self;
    %$self = @_;
    map { $self->{$_} = $default_opts{$_} if (!exists($self->{$_})) } (keys(%default_opts));
    return undef if (!$self->{'dbh'});
    my $dbh = $self->{'dbh'};
    $self->{'geth'} = $dbh->prepare("select $self->{valcol} from $self->{table} where $self->{namecol} = ?");
    $self->{'allh'} = $dbh->prepare("select $self->{namecol}, $self->{valcol} from $self->{table}");
    $self->{'cnth'} = $dbh->prepare("select count($self->{valcol}) from $self->{table} where $self->{namecol} = ?");
    $self->{'insh'} = $dbh->prepare("insert into $self->{table} ($self->{namecol}, $self->{valcol}) values(?, ?)");
    $self->{'updh'} = $dbh->prepare("update $self->{table} set $self->{valcol} = ? where $self->{namecol} = ?");
    $self->{'delh'} = $dbh->prepare("delete from $self->{table}");
    bless $self, $class;
}

sub create_table {
    my $self = shift;
    print "create table $self->{table} (id int, $self->{namecol} varchar(255), $self->{valcol} varchar(4096))\n";
    my $ct = $self->{'dbh'}->prepare("create table $self->{table} (id int, $self->{namecol} varchar(255), $self->{valcol} varchar(4096))");
    $ct->execute();
}

sub get_all {
    my $self = shift;
    my $ret;

    $self->{'allh'}->execute();
    while (my $vals = $self->{'allh'}->fetchrow_arrayref()) {
	$ret->{$vals->[0]} = $vals->[1];
    }
    $self->{'allh'}->finish;

    return $ret;
}

sub set {
    my ($self, $it, $value) = @_;

    # check to see if it exists
    $self->{'cnth'}->execute($it);
    my $vals = $self->{'cnth'}->fetchrow_arrayref();
    $self->{'cnth'}->finish;
    print "$it -> $value -> $vals->[0]\n";
    if ($vals->[0] == 0) {
	$self->{'insh'}->execute($it, $value);
    } else {
	$self->{'updh'}->execute($value, $it);
    }

    return $value;
}

sub get {
    my ($self, $it) = @_;
    $self->{'geth'}->execute($it);
    my $vals = $self->{'geth'}->fetchrow_arrayref();
    $self->{'geth'}->finish;
    return $vals->[0];
}

sub reset {
    my $self = shift;
    $self->{'delh'}->execute();
}

1;

=pod

=head1 NAME

QWizard::Storage::SQL - Stores data in a SQL database

=head1 SYNOPSIS

  my $st = new QWizard::Storage::SQL(dbh => $DBI_reference);
  $st->create_table();
  $st->set('var', 'value');
  $st->get('var');

=head1 DESCRIPTION

Stores data passed to and from a database table through a passed in
database handle reference.

=head1 AUTHOR

Wes Hardaker, hardaker@users.sourceforge.net

=head1 SEE ALSO

perl(1)

Net-Policy: http://net-policy.sourceforge.net/

=cut
