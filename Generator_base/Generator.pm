package QWizard::Generator;

use AutoLoader;
use POSIX qw(isprint);
use strict;
our $VERSION = '2.2';
use QWizard::Storage::Memory;
require Exporter;

@QWizard::Generator::ISA = qw(Exporter);
@QWizard::Generator::EXPORT = qw(qwdebug qwpref);

our $AUTOLOAD;

# just a base class.
#
# functions to implement:
#  radio

# default do-nothing subroutines.  These are optional in sub-generators.
sub do_question_end {}
sub start_questions {}
sub end_questions {}
sub do_pass {};

sub new {
    die "should not be called directly\n";
}

sub init_default_storage {
    my $self = shift;
    $self->{'datastore'} = new QWizard::Storage::Memory();
    $self->{'prefstore'} = new QWizard::Storage::Memory();
    $self->{'tmpdir'} = "/tmp" if (!$self->{'tmpdir'});
}

# widgets that have fallbacks to more minimal widgets:
sub do_textbox {
    my $self = shift;
    $self->do_entry(@_);
}

sub do_paragraph {
    my $self = shift;
    $self->do_label(@_);
}

our $have_gd_graph = eval { require GD::Graph::lines; };

our $def_width = 400;
our $def_height = 400;

sub binize_x_data {
    my ($self, $multidata, $q, $width) = @_;
    my ($minx, $maxx);

    my ($newdata, $x, $xlab);

    if (!$q->{'multidata'}) {
	$multidata = [$multidata];
    }

    foreach my $data (@$multidata) {
	if (!defined($minx) || $minx > $data->[0][0]) {
	    $minx = $data->[0][0];
	}
	if (!defined($maxx) || $maxx < $data->[$#$data][0]) {
	    $maxx = $data->[$#$data][0];
	}
    }
    my $diff = $maxx - $minx;
    if ($diff == 0) {
	print STDERR "no data to graph (time diff = 0)!\n";
	print STDERR "minx: $minx, maxx: $maxx\n";
	return [[]];
    }
    my $addative = 0;
    foreach my $data (@$multidata) {
	my $numc = $#{$data->[0]};
	foreach my $d (@$data) {
	    my $xval = int($width * (($d->[0] - $minx) / $diff));
	    if (!exists($newdata->[0][$xval])) {
		 $newdata->[0][$xval] = $d->[0];
	    }
	    for ($x = 1; $x <= $numc; $x++) {
		$newdata->[$x + $addative][$xval] = $d->[$x];
	    }
	}
	if (!$addative) {
	    # first row contained the indexes
	    $addative = -1;
	}
	$addative += $numc+1;
    }

    for (my $i = 0; $i <= $#$newdata; $i++) {
	for ($x = 0; $x <= $#{$newdata->[$i]}; $x++) {
	    if (!exists($newdata->[$i][$x])) {
		$newdata->[$i][$x] = undef;
	    }
	}
    }

    return $newdata;
}

sub do_graph_data {
    my ($self, $q, $wiz, $p, $data, $gopts) = @_;
    my ($w, $h) = ($def_width, $def_height);
    my %gopts;
    %gopts = @$gopts if ($gopts);
    $w = $gopts{'-width'} if (exists($gopts{'-width'}));
    $h = $gopts{'-height'} if (exists($gopts{'-height'}));

    if ($have_gd_graph) {
	my $gph = GD::Graph::lines->new($w, $h);
	$gph->set(@$gopts) if (defined($gopts));
	my %hg = %gopts;
	$gph->set_legend(@{$hg{'legend'}}) if (exists($hg{'legend'}));
	$data = $self->binize_x_data($data, $q, $w);
	my $plot = $gph->plot($data);
	if (!$plot) {
	    print STDERR "plot: " . $gph->error . "\n";
	    return;
	}
	
	return $plot->png ||
	  print STDERR "do_graph_data error: $gph->error\n";
    }
}

# Default storage = variable space

sub qwparam {
    my $self = shift;
    return $self->{'datastore'}->access(@_);
}

sub backup_params {
    my $self = shift;
    if ($#{$self->{'backupvars'}} > ($self->{'maxbackups'} || 10)) {
	pop @{$self->{'backupvars'}};
    }
    unshift @{$self->{'backupvars'}}, {%{$self->{'datastore'}->get_all}};
}

sub revert_params {
    my $self = shift;
    shift @{$self->{'backupvars'}};
    if ($#{$self->{'backupvars'}} > -1) {
	$self->{'datastore'}->set_all(shift @{$self->{'backupvars'}});
    } else {
	$self->{'datastore'}->set_all({});

    }
}

sub do_hidden {
    my ($self, $wiz, $name, $val) = @_;
    $self->{'datastore'}->set($name, $val);
}

sub clear_params {
    my $self = shift;
    $self->{'datastore'}->reset();
    @{$self->{'backupvars'}} = ();
}

sub get_handler {
    my ($self, $type, $q) = @_;
    use Data::Dumper;
    if (exists($self->{'typemap'}{$type})) {
	return $self->{'typemap'}{$type};
    }
}

sub add_handler {
    my ($self, $type, $fn, $argdef) = @_;
    $self->{'typemap'}{$type}{'function'} = $fn;
    $self->{'typemap'}{$type}{'argdef'} = $argdef;
}

#
# argdef format:  
# [
#   [ TYPE, NAMEorSPECIAL, DEFAULT],
#   ...
# ]
sub get_arguments {
    my ($self, $wiz, $q, $argdef, $default) = @_;
    my @args;
    for (my $i = 0; $i <= $#$argdef; $i++) {
	if (ref($argdef->[$i]) ne 'ARRAY') {
	    print STDERR "malformed argument definition: $argdef->[$i]\n";
	    push @args, undef;
	    next;
	}
	my $def = $argdef->[$i];
	if ($def->[0] eq 'default') {
	    push @args, $default;
	} elsif ($def->[0] eq 'forced') {
	    push @args, $def->[1];
	} elsif ($def->[0] eq 'values,labels') {
	    push @args, $wiz->get_values_and_labels($q, $def->[1])
	} elsif ($def->[0] eq 'multi') {
	    if (exists($q->{$def->[1]})) {
		push @args, $wiz->get_values($q->{$def->[1]});
	    } else {
		push @args, $def->[2];
	    }
	} elsif ($def->[0] eq 'single') {
	    if (exists($q->{$def->[1]})) {
		push @args, $wiz->get_value($q->{$def->[1]});
	    } else {
		push @args, $def->[2];
	    }
	} elsif ($def->[0] eq 'norecurse') {
	    if (exists($q->{$def->[1]})) {
		push @args, $wiz->get_value($q->{$def->[1]}, 1);
	    } else {
		push @args, $def->[2];
	    }
	} elsif ($def->[0] eq 'norecursemulti') {
	    if (exists($q->{$def->[1]})) {
		push @args, $wiz->get_values($q->{$def->[1]}, 1);
	    } else {
		push @args, $def->[2];
	    }
	} elsif ($def->[0] eq 'labels') {
	    if (exists($q->{$def->[1]})) {
		push @args, $wiz->get_labels($q);
	    } else {
		push @args, $def->[2];
	    }
	} else {
	    print STDERR "unknown argument type: $def->[0]\n";
	}
    }
    return \@args;
}

# preferences

sub qwpref {
    my $self = shift;
    return $self->{'prefstore'}->access(@_);
}

# file uploads

sub qw_upload_fh {
    my ($self) = shift;
    my ($it);
    my $ret;
    if (ref($self) =~ /QWizard/) {
	$it = shift;
    } else {
	$it = $self;
    }

    my $fh = new IO::File();
    $fh->open("<" . $self->qwparam($it));

    return $fh;
}

## convenince

sub make_displayable {
    my ($self, $str);
    if ($#_ > 0) {
	($self, $str) = @_;
    } else {
	($str) = @_;
    }

    if (defined($str) && $str ne '' && !isprint($str)) {
	$str = "0x" . (unpack("H*", $str))[0];
    }
    return $str;
}

## temporary file creation if needed by child classes
sub create_temp_file {
    my ($self, $sfx, $data) = @_;
    use File::Temp qw(tempfile);
    mkdir($self->{'tmpdir'}) if (! -d $self->{'tmpdir'});
    my ($fh, $filename) = tempfile("qwHTMLXXXXXX", SUFFIX => $sfx,
				   DIR => $self->{'tmpdir'});
    if (ref($data) eq 'IO::File' || ref($data) eq 'Fh') {
	while (<$data>) {
	    print $fh $_;
	}
    } else {
	print $fh $data;
    }
    $fh->close();

    return $filename;
}

## All other missing functions are errors

sub AUTOLOAD {
    my $sub = $AUTOLOAD;
    my $mod = $AUTOLOAD;
    $mod =~ s/::[^:]*$//;
    $sub =~ s/.*:://;

    die "FATAL PROBLEM: Your widget generator \"$mod\" doesn't support the \"$sub\" function";
}

1;
__END__
