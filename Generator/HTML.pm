package QWizard::Generator::HTML;

#
# isprint() appears to be broken on some machine.  This will determine if
# it's broken here and tell us how to proceed later.
#
my $use_np_isprint = 0;
if(isprint("abc\000abc") || isprint("abc\001abc") || !isprint("barra"))
{
	$use_np_isprint = 1;
}


use strict;
our $VERSION = '2.2.3';
use CGI qw(escapeHTML);
use CGI::Cookie;
require Exporter;
use QWizard::Generator;
use QWizard::Storage::CGIParam;
use QWizard::Storage::CGICookie;
use IO::File;
use POSIX qw(isprint);

@QWizard::Generator::HTML::ISA = qw(Exporter QWizard::Generator);

our %defaults = (
		 headerbgcolor => '#d18458',
		 bgcolor => '#ffa26c',
		 form_name => 'qwform',
		 tmpdir => '/tmp',
		 one_pass => 1,
	       );

our $have_gd_graph = eval { require GD::Graph::lines; };

our $redo_screen_js =
  "this.form.redo_screen.value=1; this.form.submit();";

sub new {
    my $type = shift;
    my ($class) = ref($type) || $type;
    my %self = %defaults;
    for (my $i = 0; $i <= $#_; $i += 2) {
	$self{$_[$i]} = $_[$i+1];
    }
    my $self = \%self;
    bless($self, $class);
    $self->add_handler('text',\&QWizard::Generator::HTML::do_entry,
		       [['single','name'],
			['default'],
			['forced','0'],
			['single','size'],
			['single','maxsize'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('hidetext',\&QWizard::Generator::HTML::do_entry,
		       [['single','name'],
			['default'],
			['forced','1'],
			['single','size'],
			['single','maxsize'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('textbox',\&QWizard::Generator::HTML::do_textbox,
		       [['default'],
			['single', 'width'],
			['single', 'size'],
			['single', 'height'],
			['single', 'submit'],
			['single','refresh_on_change']]);
    $self->add_handler('checkbox',\&QWizard::Generator::HTML::do_checkbox,
		       [['multi','values'],
			['default'],
			['single', 'submit'],
			['single','refresh_on_change']]);
    $self->add_handler('multi_checkbox',
		       \&QWizard::Generator::HTML::do_multicheckbox,
		       [['multi','default'],
			['values,labels'],
			['single','submit'],
			['single','refresh_on_change']]);
    $self->add_handler('menu',
		       \&QWizard::Generator::HTML::do_menu,
		       [['values,labels', "   "],
			['default'],
			['single','submit'],
			['single','refresh_on_change'],
			['single', 'name']]);
    $self->add_handler('radio',
		       \&QWizard::Generator::HTML::do_radio,
		       [['values,labels'],
			['default'],
			['single','submit'],
			['single','refresh_on_change'],
			['single','name']]);
    $self->add_handler('label',
		       \&QWizard::Generator::HTML::do_label,
		       [['multi','values']]);
    $self->add_handler('link',
		       \&QWizard::Generator::HTML::do_link,
		       [['single','linktext'],
			['single','url']]);
    $self->add_handler('paragraph',
		       \&QWizard::Generator::HTML::do_paragraph,
		       [['multi','values'],
			['single','preformatted']]);
    $self->add_handler('button',
		       \&QWizard::Generator::HTML::do_button,
		       [['single','values']]);
    $self->add_handler('table',
		       \&QWizard::Generator::HTML::do_table,
		       [['norecurse','values'],
			['norecurse','headers']]);
    $self->add_handler('bar',
		       \&QWizard::Generator::HTML::do_bar,
		       [['norecurse','values']]);
    $self->add_handler('graph',
		       \&QWizard::Generator::HTML::do_graph,
		       [['norecurse','values'],
			['norecursemulti','graph_options']]);
    $self->add_handler('image',
		       \&QWizard::Generator::HTML::do_image,
		       [['norecurse','imgdata'],
			['norecurse','image'],
			['single','imagealt'],
			['single', 'height'],
			['single', 'width']]);
    $self->add_handler('fileupload',
		       \&QWizard::Generator::HTML::do_fileupload,
		       [['default','values']]);

    $self->add_handler('unknown',
		       \&QWizard::Generator::HTML::do_unknown,
		       []);

    $self->{'datastore'} = new QWizard::Storage::CGIParam;
    $self->{'prefstore'} = new QWizard::Storage::CGICookie;

    return $self;
}

sub init_cgi {
    my $self = shift;
    if (!exists($self->{'cgi'})) {
	# we do this here late binding as possible for various reasons
	$self->{'cgi'} = new CGI;
    }
}

sub init_screen {
    my ($self, $wiz, $title) = @_;
    $self->init_cgi();
    $self->{'datastore'}->reset();

    return if ($self->{'started'} || $wiz->{'started'});
    $self->{'started'} = $wiz->{'started'} = $self->{'prefstore'}{'started'} =1;
    $self->{'first_tree'} = 1;
    my @otherargs;
    if ($self->{'cssurl'}) {
	push @otherargs, 'style', { src => $self->{'cssurl'}};
    }
    print "Content-type: text/html\n\n" if (!$self->{'noheaders'} &&
					    !$wiz->{'noheaders'});
    print $self->{'cgi'}->start_html(-title => escapeHTML($title),
				     -bgcolor => $self->{'bgcolor'}
				     || $wiz->{'bgcolor'} || "#ffffff",
				     @otherargs);

    if ($self->{'prefstore'}->{'immediate_out'} &&
	$#{$self->{'prefstore'}->{'immediate_out'}} > -1) {
	print @{$self->{'prefstore'}->{'immediate_out'}};
	delete $self->{'prefstore'}->{'immediate_out'};
    }
    print $self->{'cgi'}->start_multipart_form(-name => $self->{'form_name'}),
      "\n";
    $self->{'wizard'} = $wiz;
}

# html always waits
sub wait_for {
  my ($self, $wiz, $next, $p) = @_;
  print "<P><input type=submit value=\"" . escapeHTML($next) . "\">\n";
  $self->do_hidden($wiz, "redo_screen", 0) if (!$self->qwparam('redo_screen'));
  if ($self->qwparam('allow_refresh') || $p->{'allow_refresh'}) {
      print "<input type=submit onclick=\"$redo_screen_js\" name=redo_screen_but value=\"Refresh Screen\">\n";
  }
  print $self->{'cgi'}->end_form();
  return 1;
}

sub do_css {
    my ($self, $class, $name, $noidstr) = @_;
    if ($self->{'cssurl'}) {
	my $idstr = '';
	$idstr = $class if (!$noidstr);
	return " class=\"$class\" id=\"$idstr$name\" ";
    }
    return "";
}

sub do_question {
    my ($self, $q, $wiz, $p, $text, $qcount) = @_;
    return if (!$text && $q->{'type'} eq 'hidden');
    print "  <tr" . $self->do_css('qwquestion',$q->{'name'}) . ">";
    print "<td" . $self->do_css('qwquestiontext',$q->{'name'}) . 
      " valign=top>\n";
    if ($q->{'helptext'}) {
	print $wiz->make_help_link($p, $qcount),
	  escapeHTML($text), "</a>\n";
    } else {
	print escapeHTML($text);
    }
    if ($q->{'helpdesc'}) {

      #
      # Get the actual help text, in case this is a subroutine.
      #
      my $helptext = $q->{'helpdesc'};
      if (ref($helptext) eq "CODE") {
          $helptext = $helptext->();
      }
      print "<br><small><i>" . escapeHTML($helptext) . "</i></small>";
    }
    print "</td><td" . $self->do_css('qwquestion',$q->{'name'}, 1) . ">\n";
}

sub do_question_end {
    my ($self, $q, $wiz, $p, $qcount) = @_;

    #
    # help text
    #
    return if (!$q->{'text'} && $q->{'type'} eq 'hidden');
    print "</tr>\n";
}

sub start_questions {
    my ($self, $wiz, $p, $title, $intro) = @_;
    if ($title) {
	print $self->{'cgi'}->h1(escapeHTML($title)),"\n";
    }
    if ($intro) {
	$intro = escapeHTML($intro);
	$intro =~ s/\n\n/\n<p class=\"qwintroduction\">\n/g;
	print "<p class=\"qwintroduction\">$intro\n<p class=\"qwintroduction\">\n";
    }
    print "<table class=\"qwquestions\">\n";
    $self->{'intable'} = 1;
}

sub end_questions {
    my ($self, $wiz, $p) = @_;
    print "</table>\n";

    #
    # This focus() call should allow the user to type directly into the
    # first text box without having to click there first.
    #
    print "<script>\n";
    print "document.forms[0].elements[0].focus();\n";
    print "</script>\n";

    $self->{'started'} = $wiz->{'started'} = 0;
    delete($self->{'intable'});
}

sub do_pass {
    my ($self, $wiz, $name) = @_;
    $self->do_hidden($wiz, $name, $self->qwparam($name)) 
      if ($self->qwparam($name) ne '');
}

##################################################
# Bar support
##################################################

sub start_bar {
    my ($self, $wiz, $name) = @_;
    if ($self->{'intable'}) {
	print "</table>\n";
    }
    print "<div " . $self->do_css('qwbar',$name) . ">\n";
}

sub end_bar {
    my ($self, $wiz, $name) = @_;
    print "</div>\n";
    if ($self->{'intable'}) {
	print "<table class=\"qwquestions\">\n";
    }
}

sub do_bar {
    my ($self, $q, $wiz, $p, $widgets) = @_;

    $self->start_bar($wiz, undef);
    $self->do_a_table([$widgets], 0, $wiz, $q, $p);
    $self->end_bar($wiz, 'Questions');
}

sub do_top_bar {
    my ($self, $q, $wiz, $p, $widgets) = @_;

    $self->do_a_table([$widgets], 0, $wiz, $q, $p);
}

##################################################
# widgets
##################################################

sub do_button {
    my ($self, $q, $wiz, $p, $vals) = @_;
    print "<input" . $self->do_css('qwbutton',$q->{'name'}) . " type=submit name=\"$q->{'name'}\" value=\"" . $vals . "\">\n";
}

sub do_checkbox {
    my ($self, $q, $wiz, $p, $vals, $def, $submit, $refresh_on_change) = @_;
    $vals = [1, 0] if ($#$vals == -1);
    my $otherstuff;
    if ($def == $vals->[0]) {
	$otherstuff .= " checked";
    }
    if ($#$vals > -1) {
	$otherstuff .= " value=\"" . escapeHTML($vals->[0]) . "\"";
    }
    if ($submit) {
	$otherstuff .= " onclick=\"this.form.submit()\"";
    }
    if ($refresh_on_change) {
	$otherstuff .= " onclick=\"$redo_screen_js\"";
    }
    print "<input" . $self->do_css('qwcheckbox',$q->{'name'}) . " type=checkbox name=\"$q->{name}\"$otherstuff>";
}

sub do_multicheckbox {
    my ($self, $q, $wiz, $p, $defs, $vals, $labels,
	$submit, $refresh_on_change) = @_;
    print "<table>";
    my $count = -1;
    my ($startname, $endname);
    foreach my $v (@$vals) {
	$count++;
	my $otherstuff;
	$otherstuff .= "checked" if ($defs->[$count]);
	if ($submit) {
	    $otherstuff .= " onclick=\"this.form.submit()";
	}
	if ($refresh_on_change) {
	    $otherstuff .= " onclick=\"$redo_screen_js\"";
	}
	my $l = (($labels->{$v}) ? $labels->{$v} : "$v");
	print "<tr><td>" . escapeHTML($l)  . "</td>\n";
	print "<td><input" . $self->do_css('qwmulticheckbox',$q->{'name'}) . " $otherstuff value=\"" . escapeHTML($v) . 
	  "\" type=checkbox name=\"$q->{name}$l\"></td></tr>";
	# XXX: hack:
	push @{$wiz->{'passvars'}},$q->{'name'} . $v;
	$startname = "$q->{name}$l" if ($count == 0);
	$endname = "$q->{name}$l" if ($count == $#$vals);
    }

    print "</table>";

    #Javascript for setting/unsetting/toggling buttons
    print "

<script language=\"JavaScript\">
    function $q->{name}_setall() {
      var doit = false;
      for (i=0; i<document.qwform.elements.length; i++) {
        if (document.qwform.elements[i].type == \"checkbox\") {
          if (document.qwform.elements[i].name == \"$startname\") {
            doit = true;
          }
          if (doit) {
            document.qwform.elements[i].checked = true;
          }
          if (document.qwform.elements[i].name == \"$endname\") {
            doit = false;
          }
        }
      }
    }

    function $q->{name}_unsetall() {
      var doit = false;
      for (i=0; i<document.qwform.elements.length; i++) {
        if (document.qwform.elements[i].type == \"checkbox\") {
          if (document.qwform.elements[i].name == \"$startname\") {
            doit = true;
          }
          if (doit) {
            document.qwform.elements[i].checked = false;
          }
          if (document.qwform.elements[i].name == \"$endname\") {
            doit = false;
          }
        }
      }
    }

    function $q->{name}_toggleall() {
      var doit = false;
      for (i=0; i<document.qwform.elements.length; i++) {
        if (document.qwform.elements[i].type == \"checkbox\") {
          if (document.qwform.elements[i].name == \"$startname\") {
            doit = true;
          }
          if (doit) {
            if (document.qwform.elements[i].checked) {
              document.qwform.elements[i].checked = false;
            } else {
              document.qwform.elements[i].checked = true;
            }
          }
          if (document.qwform.elements[i].name == \"$endname\") {
            doit = false;
          }
        }
      }
    }
	    ";
#     foreach my $boxname (@boxnames) {
# 	print " document.qwform.try1.checked=true;\n";
# #	print " document.qwform.\"$boxname\".checked=true;\n";
#     }
    print "
</script>

<a href=\"javascript:$q->{name}_setall()\">[Set All]</a>
<a href=\"javascript:$q->{name}_unsetall()\">[Unset All]</a>
<a href=\"javascript:$q->{name}_toggleall()\">[Toggle All]</a>

";

}

sub do_radio {
    my ($self, $q, $wiz, $p, $vals, $labels, $def,
	$submit, $refresh_on_change, $name) = @_;
    my @stuff;
    push @stuff, -onclick, "this.form.submit()" if ($submit);
    push @stuff, -onclick, "$redo_screen_js" if ($refresh_on_change);

    print $self->{'cgi'}->radio_group(-name => $name,
				      -id => "qwradio$name",
				      -class => 'qwradio',
				      -values => $vals,
				      -linebreak => 'true',
				      -labels => $labels,
				      -override => 1,
				      -default => $def,
				      @stuff),"\n";
}


sub do_label {
    my ($self, $q, $wiz, $p, $vals, $def) = @_;
    if (defined ($vals)) {
	my @labs = @$vals;  # copy this so map doesn't modify the source
	map { $_ = escapeHTML($_) } @labs;
	print "<span" . $self->do_css('qwlabel',$q->{'name'}) . ">" .
	  join("<br>", @labs) . "</span>\n";
    }
}

sub do_link {
    my ($self, $q, $wiz, $p, $text, $url) = @_;
    print $self->{'cgi'}->a({href => $url,
			     id => $q->{'name'},
			     class => 'qwlink' . $q->{'name'}}, $text);
}

sub do_paragraph {
    my ($self, $q, $wiz, $p, $vals, $preformatted) = @_;
    my @labs = @$vals;  # copy this so map doesn't modify the source
    map { $_ = escapeHTML($_) } @labs;
    if ($preformatted) {
	print "<pre" . $self->do_css('qwparagraph',$q->{'name'}) . ">\n",
	  @labs,"</pre>\n";
    } else {
	print "<span" . $self->do_css('qwparagraph',$q->{'name'}) . ">" .
	  join("<br><br>", @labs) . "</span>\n";
    }
}

sub do_menu {
    my ($self, $q, $wiz, $p, $vals, $labels, $def,
	$submit, $refresh_on_change, $name) = @_;
    my @stuff;
    push @stuff, -onchange, "this.form.submit()" if ($submit);
    push @stuff, -onchange, "$redo_screen_js" if ($refresh_on_change);

    print $self->{'cgi'}->popup_menu(-name => $name,
				     -id => 'qwmenu' . $name,
				     -class => 'qwmenu',
				     -values => $vals,
				     -override => 1,
				     -labels => $labels,
				     -default => $def,
				     @stuff);
}

sub do_fileupload {
    my ($self, $q, $wiz, $p, $vals, $labels, $def) = @_;

    push @{$wiz->{'passvars'}}, $q->{'name'} . "_qwf";
    print $self->{'cgi'}->filefield(-name => $q->{name},
				    -id => 'qwmenu' . $q->{'name'},
				    -class => 'qwmenu',
				    -override => 1,
				    -default => $def);
}

sub qw_upload_file {
    my ($self) = shift;
    my ($it);
    my $ret;
    if (ref($self) =~ /QWizard/) {
	$it = shift;
    } else {
	$it = $self;
    }
    if (!exists($self->{'cgi'})) {
	$self->{'cgi'} = new CGI;
    }

    my $fn;
    if (!$self->qwparam($it . "_qwf")) {
	# copy the file to a local qwizard copy of it

	# XXX: check error if undef; puts it in $self->{'cgi'}->cgi_error
	my $fh = $self->{'cgi'}->upload($it);
	$fn = $self->create_temp_file('.tmp', $fh);
	$fn =~ s/(.*)\///;
	$fn =~ s/$self->{'tmpdir'}\/+//;
	$fn =~ s/\.tmp$//;
	print STDERR "*" x 20 . " -> $it -> $fn -> " . ref($fh) . "++\n";
	$self->qwparam($it . "_qwf", $fn);
    } else {
	$fn = $self->qwparam($it . "_qwf");
	$fn =~ s/[^a-zA-Z0-9]//;
	print STDERR "*" x 20 . " -> $it -> $fn \n";
    }

    $fn = $fn . ".tmp";
    $fn = $self->{'tmpdir'} . "/" . $fn;
    return $fn;
}

sub qw_upload_fh {
    my ($self) = shift;
    my ($it);
    my $ret;
    if (ref($self) =~ /QWizard/) {
	$it = shift;
    } else {
	$it = $self;
    }
    if (!exists($self->{'cgi'})) {
	$self->{'cgi'} = new CGI;
    }

    my $fn;
    if (!$self->qwparam($it . "_qwf")) {
	# copy the file to a local qwizard copy of it

	# XXX: check error if undef; puts it in $self->{'cgi'}->cgi_error
	my $fh = $self->{'cgi'}->upload($it);
	print STDERR "*" x 20 . ref($fh) . "++\n";
	$fn = $self->create_temp_file('.tmp', $fh);
	$fn =~ s/(.*)\///;
	$fn =~ s/$self->{'tmpdir'}\/+//;
	$fn =~ s/\.tmp$//;
	$self->qwparam($it . "_qwf", $fn);
    } else {
	$fn = $self->qwparam($it . "_qwf");
	$fn =~ s/[^a-zA-Z0-9]//;
	print STDERR "*" x 80 . $fn,"\n";
    }

    $fn = $fn . ".tmp";
    $fn = $self->{'tmpdir'} . "/" . $fn;

    my $retfh = new IO::File;
    $retfh->open("<$fn");

    return $retfh;
}

sub do_entry {
    my ($self, $q, $wiz, $p, $name, $def, $hide, $size, $maxsize,
	$submit, $refresh_on_change) = @_;
    my $otherinfo;
    if ($size) {
	$otherinfo .= " size=\"$size\"";
    } else {
	if ($maxsize) {
	    $otherinfo .= " size=\"$maxsize\"";
	}
    }
    if ($maxsize) {
	$otherinfo .= " maxlength=\"$maxsize\"";
    }
    if ($def ne '') {
	$otherinfo .= " value=\"" . escapeHTML($def) . "\"";
    }
    if ($submit) {
	$otherinfo .= " onchange=\"this.form.submit()\"";
    }
    if ($refresh_on_change) {
	$otherinfo .= " onclick=\"$redo_screen_js\"";
    }

    #
    # If the hide flag was set, we'll treat this as unprintable text.
    #
    if ($hide) {
	$otherinfo .= " type=\"password\"";
    }

    print "<input" . $self->do_css('qwtext',$q->{'name'}) . 
      " name=\"$name\" $otherinfo>";
}

sub do_textbox {
    my ($self, $q, $wiz, $p, $def, $width, $size, $height, $submit, $refresh_on_change) = @_;
    my $otherinfo;
    if ($size || $width) {
	$size = $size || $width;
	$otherinfo .= " cols=\"$size\"";
    }
    if ($height) {
	$otherinfo .= " rows=\"" . $height . "\"";
    }
    if ($submit) {
	$otherinfo .= " onchange=\"this.form.submit()\"";
    }
    if ($refresh_on_change) {
	$otherinfo .= " onclick=\"$redo_screen_js\"";
    }
    print "<textarea" . $self->do_css('qwtextbox',$q->{'name'}) . 
      " name=\"$q->{name}\" $otherinfo>" . escapeHTML($def) . "</textarea>";
}

sub do_error {
    my ($self, $q, $wiz, $p, $err) = @_;
    my $name = ($q ? $q->{'name'} : '');
    print "<tr" . $self->do_css('qwerrorrow',$name) . "><td" .
      $self->do_css('qwerrorcol',$name) .
	" colspan=3><font color=red>" . escapeHTML($err) .
	  "</font></td></tr>\n";
}

sub do_separator {
    my ($self, $q, $wiz, $p, $text) = @_;
    if ($text eq "") {
	$text = "&nbsp";
    } else {
	$text = escapeHTML($text);
    }
    my $name = (ref($q) eq 'HASH') ? $q->{'name'} : "";
    print "  <tr" . $self->do_css('qwseparatorrow',$name) . 
      "><td" . $self->do_css('qwseparatorcol',$name) . 
	" colspan=3>$text</td></tr>";
}

sub do_hidden {
    my ($self, $wiz, $name, $val) = @_;
    print "<input type=hidden name=\"$name\" value=\"" . 
      escapeHTML($val) . "\">\n";
    $self->qwparam($name,$val);
}

sub do_unknown {
    my ($self, $q, $wiz, $p) = @_;

    print "<font color=\"red\">Error: Unhandled question type '$q->{type}' in primary '$p->{module_name}'.  It is highly likely that this page will not function properly after this point.</font>\n";
}

##################################################
# Display
##################################################

sub do_table {
    my ($self, $q, $wiz, $p, $table, $headers) = @_;
    my $color = $self->{'tablebgcolor'} || $self->{'bgcolor'};
    print "<table" . $self->do_css('qwtable',$q->{'name'}) .
      " bgcolor=$color border=1>\n";

    if ($headers) {
	print " <tr " . $self->do_css('qwtableheaderrow',$q->{'name'}) .
	  "bgcolor=\"$self->{headerbgcolor}\">\n";
	foreach my $column (@$headers) {
	    print "<th" . $self->do_css('qwtableheader',$q->{'name'}) .
	      ">" . ($column || "&nbsp;") . "</th> ";
	}
	print " </tr>\n";
    }

    $self->do_a_table($table, 1, $wiz, $q, $p);
    print "</table>\n";
}

sub do_a_table {
    my ($self, $table, $started, $wiz, $q, $p) = @_;
    print "<table" . $self->do_css('qwsubtable',$q->{'name'}) . ">"
      if (!$started);
    foreach my $row (@$table) {
	print " <tr" . $self->do_css('qwtablerow',$q->{'name'}) . ">\n";
	foreach my $column (@$row) {
	    print "<td>";
	    if (ref($column) eq "ARRAY") {
	        $self->do_a_table($column, 0, $wiz, $q, $p);
	    } elsif (ref($column) eq "HASH") {
		print "<table" . $self->do_css('qwtablewidget',$q->{'name'}) .
		  ">\n";
		my $param = $wiz->ask_question($p, $column);
		push @{$wiz->{'passvars'}}, $param;
		print "</table>\n";
	    } else {
		my $val = $self->make_displayable($column);
		print (defined($val) && $val ne "" ? $val : "&nbsp;");
	    }
	    print "</td>";
	}
	print " </tr>\n";
    }
    print "</table>\n" if (!$started);
}

sub do_graph {
    my $self = shift;
    my ($q, $wiz, $p, $data, $gopts) = @_;

    if ($have_gd_graph) {
	my $file = $self->create_temp_file('.png', $self->do_graph_data(@_));
	$file =~ s/(.*)\///;
	
	# XXX: net-policy specific hack!
	print "<img" . $self->do_css('qwgraph',$q->{'name'}) .
	  " src=\"?webfile=$file\">\n";
    } else {
	print "graphs not supported without additional software\n";
    }
}

########################################################################
#
sub do_image {
	my $self = shift;
	my ($q, $wiz, $p, $imgdata, $imgfile, $alt, $height, $width) = @_;
	my $image;
	
	if ($imgdata) {
	    # store the image in a temporary file
	    $image = $self->create_temp_file('.png', $imgdata);
	    $image =~ s/(.*)\///;
	} else {
	    $image = $imgfile;
	}
	my $imagesrc = "src=\"?webfile=$image\"";

	#
	# If an alt tag was specified, create the alt image message.
	#
	my $altmsg = "alt=\"Broken Image - $image\"";
	if($alt ne "")
	{
		$altmsg = "alt=\"$alt\"";
	}

	#
	# If a height tag was specified, add the image height.
	#
	my $hmsg   = " ";
	if($height ne "")
	{
		$hmsg = "height=\"$height\"";
	}

	#
	# If a width tag was specified, add the image width.
	#
	my $wmsg  = " ";
	if($width ne "")
	{
		$wmsg = "width=\"$width\"";
	}

	print "<img" . $self->do_css('qwimage',$q->{'name'}) .
	  " $imagesrc $altmsg $hmsg $wmsg border=1>\n";
}

##################################################
#
# Automatic updating for monitors.
#

sub do_autoupd
{
	my ($self, $secs) = @_;
	my $msecs = $secs * 1000;

	if($secs eq "")
	{
		return;
	}

# warn "\ndo_autoupd:  sleeping for $secs seconds\n";

	#
	# Javascript for automatically updating the screen.
	#
	print <<EOF;
	<script language="JavaScript">
	function autoupd_$secs() {
		document.qwform.submit();
	}

	setTimeout("autoupd_$secs()",$msecs);

	</script>
EOF

}

##################################################
# Trees
##################################################

#TODO: Support passing in a hash for tree data (instead of just a function)

sub do_tree {
    my ($self, $q, $wiz, $p, $labels) = @_;

    my $treename = $q->{'name'} || 'tree';

    my $expanded = $self->qwparam("${treename}_expanded") || $q->{'root'};
    my @expand = split(/,/, $expanded);
    # redo_screen values:
    #  1: selects a label
    #  2: expands a branch
    #  3: collapses a branch
    my $redo = $self->qwparam("redoing_now");

    if ($redo == 2 && $self->qwparam("${treename}_collapse")) {
	push @expand, $self->qwparam("${treename}_collapse");
    } elsif ($redo == 3 && $self->qwparam("${treename}_collapse")) {
	@expand = grep(!($_ eq $self->qwparam("${treename}_collapse")),@expand);
    }


    my $selected = $self->qwparam($treename);
    if ($selected) {
	#if the selected node is hidden inside a collapsed branch, select the
	#closest visible node. Although it changes the selected node, this seems
	#better than the possibly-confusing situation of the selected node being
	#hidden beneath an unexpanded node.
	my $cur = $selected;
	until ($cur eq $q->{'root'}) {
	    $cur = get_name($q->{'parent'}->($wiz, $cur) || return);
	    my @tmp = grep($_ eq $cur, @expand);
	    unless ($#tmp > -1) {
		$selected = $cur;
	    }
	}
    } else { #ensure that the default is initially visible
	$selected = $q->{'default'} || $q->{'root'} || return;
	my $cur = $selected;
	until ($cur eq $q->{'root'}) {
	    $cur = get_name($q->{'parent'}->($wiz, $cur) || return);
	    push @expand, $cur;
	}
    }

    $expanded = join(',', @expand);
    $self->do_hidden($wiz, "${treename}_expanded", $expanded);
    if ($self->{'first_tree'}) { #only one hidden value for redo_screen
	$self->{'first_tree'} = 0;
    }
    $self->do_hidden($wiz, $treename, $selected);

    #holds the name of a node that needs to be collapsed or expanded
    $self->do_hidden($wiz, "${treename}_collapse", ''); 

    #Javascript for expanding/collapsing/selecting
    print <<EOF;
<script language="JavaScript">
    function ${treename}_select(item, oper) {
	if (oper == 1) {
	    document.qwform.${treename}.value=item;
	} else {
	    document.qwform.${treename}_collapse.value=item;
	}
	document.qwform.redo_screen.value=oper;
	document.qwform.submit();
    }
</script>
EOF

    print "<div " . $self->do_css('qwtree',$treename) . ">\n";
    print_branch($wiz, $q, $q->{'root'}, $selected, 0, $labels, @expand);
    print "</div>\n";
}

sub get_name {
    my $node = shift;

    if (ref($node) eq 'HASH') {
	return $node->{'name'};
    } else {
	return $node;
    }
}

#recursively print out the tree
sub print_branch {
    # XXX: css this
    my ($wiz, $q, $cur, $selected, $nest, $labels, @expand) = @_;

    print "<br>" if $nest;
    for my $i (1 .. (5 * $nest)) { print "&nbsp;"; }

    my $children = $q->{'children'}->($wiz, get_name($cur));
    if ($#$children > -1) {
	my @ans = grep($_ eq get_name($cur), @expand); 
	if ($#ans > -1) { #is it expanded?
	    make_link('minus', 3, $cur, $selected, $q, $labels);
	    foreach my $child (@$children) {
		print_branch($wiz, $q, $child, $selected, $nest + 1, $labels, @expand);
	    }
	} else {
	    make_link('plus', 2, $cur, $selected, $q, $labels);
	}
    } else {
	make_link('blank', 0, $cur, $selected, $q, $labels);
    }
}

# prints a single node, and any required links, etc
sub make_link {
    # XXX: css this
    my ($imgtype, $oper, $cur, $selected, $q, $labels) = @_;
    my $name = get_name($cur);
    my $treename = $q->{'name'} || 'tree';
    print "<a href=\"javascript:${treename}_select('$name', $oper)\">" if $oper;
    print "<img src=\"?webfile=tree_$imgtype.png\" border=0>";
    print "</a>" if $oper;
    print "&nbsp;";
    my $label;
    if (ref($cur) eq 'HASH') {
	$label = $cur->{'label'};
    }
    $label = $label || $labels->{$name} || $name;
    if ($name eq $selected && $q->{'name'}) { 
	print "<b>$label</b>";
    } else {
	print "<a href=\"javascript:${treename}_select('$name', 1);\">" if $q->{'name'};
	print $label;
	print "</a>" if $q->{'name'};
	print "\n";
    }
}



##################################################
# action confirm
##################################################

sub start_confirm {
    my ($self, $wiz) = @_;

    print "<h1 class=\"qwconfirmtitle\">Wrapping up.</h1>\n";
    print $self->{'cgi'}->start_form(),"\n";
    print "<ul class=\"qwconfirmtop\">\n" .
      "  <p>Do you want to commit the following changes:\n";
    print "<ul class=\"qwconfirmwrap\">\n";
}

sub end_confirm {
    my ($self, $wiz) = @_;
    print "</ul></ul>\n";
    # XXX: css these.  id or class?
    print "<input type=submit name=wiz_confirmed value=\"Commit\">\n";
    print "<input type=submit name=wiz_canceled value=\"Cancel\">\n";
    print $self->{'cgi'}->end_form();
    $self->{'started'} = $wiz->{'started'} = 0;
}

sub do_confirm_message {
    my ($self, $wiz, $msg) = @_;
    print "<li class=\"confirmmsg\">" . $self->{'cgi'}->escapeHTML($msg) . "\n";
}

sub canceled_confirm {
    my ($self, $wiz) = @_;
    print $self->{'cgi'}->h1("canceled");
    print "<a href=\"$wiz->{top_location}\">Return to Top</a>\n";
    $self->{'started'} = $wiz->{'started'} = 0;
}

##################################################
# actions
##################################################

sub start_actions {
    my ($self, $wiz) = @_;
    print $self->{'cgi'}->h1('Processing your request...');
    print "<div class=\"qwactions\">\n";
    # XXX: css pre or remove and style qwactions
    print "<pre>\n";
}

sub end_actions {
    my ($self, $wiz) = @_;
    print "</pre>\n";
    print "</div>\n";
    print $self->{'cgi'}->h2('Done!');
    print "<a href=\"$wiz->{top_location}\">Return to Top</a>\n";
    $self->{'started'} = $wiz->{'started'} = 0;
}

sub do_action_output {
    my ($self, $wiz, $action) = @_;
    print "<div class=\"qwaction\">" . escapeHTML($action) . "</div>\n";
}

sub do_action_error {
    my ($self, $wiz, $errstr) = @_;
    print "<font color=red size=+1><div class=\"qwactionerror\">ERROR: <b>" . escapeHTML($errstr) .
      "</b></div></font>\n";
}

sub make_displayable {
    my ($self, $str);
    if ($#_ > 0) {
	($self, $str) = @_;
    } else {
	($str) = @_;
    }

    my $transit = 0;

    #
    # If we have a broken isprint(), do the check ourselves.  Otherwise,
    # use the builtin.
    #
    if($use_np_isprint == 1) {
	$transit = ($str =~ /[^\w\s!\@\#\$\%\^\&\*\(\)\.]/);
    }
    else {
	$transit = (!isprint($str));
    }

    #
    # If translation is required, convert the string to its hex equivalent.
    #
    if(length($str) != 0 && $transit == 1) {
        $str = "0x" . (unpack("H*", $str))[0];
    }

    # properly escape any html
    if (!$self || !exists($self->{'noescapehtml'})) {
	$str = escapeHTML($str);
    }

    return $str;
}

1;
