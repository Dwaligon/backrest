####################################################################################################################################
# DOC LATEX MODULE
####################################################################################################################################
package BackRestDoc::Latex::DocLatex;

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
use BackRestDoc::Latex::DocLatexSection;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_DOC_LATEX                                           => 'DocHtmlSite';

use constant OP_DOC_LATEX_NEW                                       => OP_DOC_LATEX . '->new';
use constant OP_DOC_LATEX_PROCESS                                   => OP_DOC_LATEX . '->process';

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
        $self->{var},
        $self->{oSite},
        $self->{oRender},
        $self->{oReference},
        $self->{strXmlPath},
        $self->{strLatexPath},
        $self->{strPreambleFile},
        $self->{bExe}
    ) =
        logDebugParam
        (
            OP_DOC_LATEX_NEW, \@_,
            {name => 'oVariable'},
            {name => 'oSite'},
            {name => 'oRender'},
            {name => 'oReference'},
            {name => 'strXmlPath'},
            {name => 'strLatexPath'},
            {name => 'strPreambleFile'},
            {name => 'bExe'}
        );

    # Remove the current html path if it exists
    if (-e $self->{strLatexPath})
    {
        executeTest("rm -rf $self->{strLatexPath}/*");
    }
    # Else create the html path
    else
    {
        mkdir($self->{strLatexPath})
            or confess &log(ERROR, "unable to create path $self->{strLatexPath}");
    }

    # Create the footer
    $self->{strFooter} = 'Copyright © 2015' . (strftime('%Y', localtime) ne '2015' ?  '-' . strftime('%Y', localtime) : '') .
                         ', The PostgreSQL Global Development Group, <a href="{[github-url-license]}">MIT License</a>.  Updated ' .
                         strftime('%B ', localtime) . trim(strftime('%e,', localtime)) . strftime(' %Y.', localtime);

    ${$self->{oSite}}{common}{strFooter} = $self->{strFooter};
    ${$self->{oSite}}{common}{oRender} = $self->{oRender};

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# variableReplace
#
# Replace variables in the string.
####################################################################################################################################
sub variableReplace
{
    my $self = shift;
    my $strBuffer = shift;
    my $bVerbatim = shift;

    if (!defined($strBuffer))
    {
        return undef;
    }

    foreach my $strName (sort(keys(%{$self->{var}})))
    {
        my $strValue = $self->{var}{$strName};

        if (!defined($bVerbatim) || !$bVerbatim)
        {
            $strValue =~ s/\_/\\_/g;
        }

        $strBuffer =~ s/\{\[$strName\]\}/$strValue/g;
    }

    return $strBuffer;
}

#
# ####################################################################################################################################
# # variableGet
# #
# # Get the current value of a variable.
# ####################################################################################################################################
# sub variableGet
# {
#     my $self = shift;
#     my $strKey = shift;
#
#     return ${$self->{var}}{$strKey};
# }

####################################################################################################################################
# process
#
# Generate the site html
####################################################################################################################################
sub process
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my $strOperation = logDebugParam(OP_DOC_LATEX_PROCESS);

    # # Copy the css file
    # my $strCssFileDestination = "$self->{strHtmlPath}/default.css";
    # copy($self->{strCssFile}, $strCssFileDestination)
    #     or confess &log(ERROR, "unable to copy $self->{strCssFile} to ${strCssFileDestination}");

    # # Render pages
    # my $oSite = $self->{oSite};
    #
    # foreach my $strPageId (sort(keys($$oSite{'page'})))
    # {
    #     # Save the html page
    #     fileStringWrite("$self->{strHtmlPath}/${strPageId}.html",
    #                     $self->variableReplace((new BackRestDoc::Html::DocHtmlPage($self, $strPageId, $self->{bExe}))->process()),
    #                     false);
    # }

    my $strLatex = $self->variableReplace(fileStringRead($self->{strPreambleFile}));
    $strLatex .= $self->variableReplace((new BackRestDoc::Latex::DocLatexSection($self, 'user-guide', $self->{bExe}))->process());
    $strLatex .= "\n% " . ('-' x 130) . "\n% End document\n% " . ('-' x 130) . "\n\\end{document}\n";

    my $strLatexFileName = "$self->{strLatexPath}/pgBackrest-UserGuide.tex";

    fileStringWrite($strLatexFileName, $strLatex, false);

    executeTest("pdflatex -output-directory=$self->{strLatexPath} $strLatexFileName");
    executeTest("pdflatex -output-directory=$self->{strLatexPath} $strLatexFileName");

    # Return from function and log return values if any
    logDebugReturn($strOperation);
}

1;
