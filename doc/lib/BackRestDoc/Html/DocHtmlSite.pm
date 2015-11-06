####################################################################################################################################
# DOC HTML SITE MODULE
####################################################################################################################################
package BackRestDoc::Html::DocHtmlSite;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Data::Dumper;
use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);
use File::Copy;
use POSIX qw(strftime);
use Storable qw(dclone);

use lib dirname($0) . '/../lib';
use BackRest::Common::Log;
use BackRest::Common::String;
use BackRest::FileCommon;
use BackRest::Version;

use lib dirname($0) . '/../test/lib';
use BackRestTest::Common::ExecuteTest;

use BackRestDoc::Common::DocConfig;
use BackRestDoc::Common::DocManifest;
use BackRestDoc::Html::DocHtmlPage;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_DOC_HTML_SITE                                       => 'DocHtmlSite';

use constant OP_DOC_HTML_SITE_NEW                                   => OP_DOC_HTML_SITE . '->new';
use constant OP_DOC_HTML_SITE_PROCESS                               => OP_DOC_HTML_SITE . '->process';

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;       # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    $self->{strClass} = $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{oManifest},
        $self->{oReference},
        $self->{strXmlPath},
        $self->{strHtmlPath},
        $self->{strCssFile},
        $self->{strHtmlRoot},
        $self->{bExe}
    ) =
        logDebugParam
        (
            OP_DOC_HTML_SITE_NEW, \@_,
            {name => 'oManifest'},
            {name => 'oReference'},
            {name => 'strXmlPath'},
            {name => 'strHtmlPath'},
            {name => 'strCssFile'},
            {name => 'strHtmlRoot'},
            {name => 'bExe'}
        );

    # Remove the current html path if it exists
    if (-e $self->{strHtmlPath})
    {
        executeTest("rm -rf $self->{strHtmlPath}/*");
    }
    # Else create the html path
    else
    {
        mkdir($self->{strHtmlPath})
            or confess &log(ERROR, "unable to create path $self->{strHtmlPath}");
    }

    $self->{oManifest}->variableSet('footer',
        'Copyright © 2015' . (strftime('%Y', localtime) ne '2015' ?  '-' . strftime('%Y', localtime) : '') .
        ', The PostgreSQL Global Development Group, <a href="{[github-url-license]}">MIT License</a>.  Updated ' .
        strftime('%B ', localtime) . trim(strftime('%e,', localtime)) . strftime(' %Y.', localtime));

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# process
#
# Generate the site html
####################################################################################################################################
sub process
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my $strOperation = logDebugParam(OP_DOC_HTML_SITE_PROCESS);

    # Copy the css file
    my $strCssFileDestination = "$self->{strHtmlPath}/default.css";
    copy($self->{strCssFile}, $strCssFileDestination)
        or confess &log(ERROR, "unable to copy $self->{strCssFile} to ${strCssFileDestination}");

    foreach my $strPageId ($self->{oManifest}->renderOutList(RENDER_TYPE_HTML))
    {
        # Save the html page
        fileStringWrite("$self->{strHtmlPath}/${strPageId}.html",
                        $self->{oManifest}->variableReplace((new BackRestDoc::Html::DocHtmlPage($self->{oManifest},
                            $strPageId, $self->{bExe}))->process()),
                        false);
    }

    # Return from function and log return values if any
    logDebugReturn($strOperation);
}

1;
