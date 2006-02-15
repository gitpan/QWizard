#!/usr/bin/perl

use QWizard;
use QWizard::API;

%primaries =
  (
   testscreen =>
   {
    title => 'Widget test screen',
    introduction => 'this is the introduction area',
    topbar => [qw_menu('topprimenu','',
		       [qw(menuopt1 menuopt2 menuopt3)])],
    questions =>
    [
     qw_label("label:","label text"),
     qw_paragraph("paragraph:","paragraph text " x 20),
     qw_text('textn',"text:", default => "test input",
	     helpdesc => 'short help'),
     {name => 'hidetextn', type => 'hidetext', text => 'hidetext:',
      helpdesc => 'short help', helptext => 'long help'},
     qw_textbox('textboxn',"textbox:"),
     qw_label("seperator:","should be a break after this question line"),
     "",
     qw_checkbox('checkboxn',"checkbox:", 'on', 'off', default => 'off'),
     qw_menu('menun','menu:',{ menuval1 => 'menulabel1',
			       menuval2 => 'menulabel2',
			       menuval3 => 'menulabel3'},
	     default => 'menuval2'),
     qw_radio('radion','radio:',{ radioval1 => 'radiolabel1',
				  radioval2 => 'radiolabel2',
				  radioval3 => 'radiolabel3'},
	      default => 'radioval2'),
     { type => 'fileupload',
       text => 'fileupload:',
       name => 'fileuploadn',},
     { type => 'filedownload',
       text => 'Download a file:',
       name => 'bogusdown',
       datafn => 
       sub { 
	   my $fh = shift;
	   print $fh "hello world: menun=" . qwparam('menun') . "\n";
       }
     },
     { type => 'multi_checkbox',
       text => 'multi_checkbox:',
       labels => [qw(mcheckvalue1 mchecklabel1 mcheckvalue2 mchecklabel2)],
       name => 'multi_checkboxn'},

      { type => 'bar',
        name => 'testbar',
        values => [[ qw_button('testbarbut','',1,'My Bar Button1'),
		     qw_menu('testbarmenu','',['Bar Menu opt 1',
					       'Bar Menu opt 2',])]]
      },

     { type => 'table',
       text => 'table:',
       headers => [['header1','header2']],
       values => [[['r1c1', 'r1c2'],
		   [ [['subr1c1','subr1c2'],['subr2c1','subr2c2']],
		     qw_text("subwidgetn","sub widget:")
		   ]]]},
     { type => 'image',
       imagealt => 'alt name',
       text => 'image:',
       image => 'smile.png'
     },
     { type => 'button',
       name => 'buttonn',
       text => 'button:',
       values => 'button text',
       default => 'button val'},

#      { type => 'graph',
#        text => 'graph:',
#        values => [[1,2,3,4],[6,5,4,8]],
#     }
    ],

    actions_descr =>
    ['Description of how we will use various values: @textn@,@menun@,...'],

    actions =>
    ["msg:results of widget twiddles:",
     sub {
	 my @results;
	 foreach my $i (qw(textn hidetextn textboxn checkboxn menun radion 
			   buttonn subwidgetn fileuploadn
			   testbarmenu testbarbut
			   multi_checkboxnmcheckvalue1
			   multi_checkboxnmcheckvalue2 )) {
	     push @results,
	       sprintf("msg: %-15s: %s", $i, qwparam($i));
	 }
	 return \@results;
     }]
    }
  );

my $wiz = new QWizard(primaries => \%primaries,
		      topbar => [qw_menu('File','',['File','opt1','opt2'])],
		      title => "The Widget Test Wizard");
$wiz->magic('testscreen');
