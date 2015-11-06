####################################################################################################################################
# DOC LATEX SECTION MODULE
####################################################################################################################################
package BackRestDoc::Latex::DocLatexSection;
use parent 'BackRestDoc::Common::DocRender';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Data::Dumper;
use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);
use File::Copy;
use Storable qw(dclone);

use lib dirname($0) . '/../lib';
use BackRest::Common::Ini;
use BackRest::Common::Log;
use BackRest::Common::String;
use BackRest::Config::ConfigHelp;
use BackRest::FileCommon;

use BackRestDoc::Common::DocManifest;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_DOC_LATEX_SECTION                                   => 'DocLatexSection';

use constant OP_DOC_LATEX_SECTION_CONFIG_PROCESS                    => OP_DOC_LATEX_SECTION . '->configProcess';
use constant OP_DOC_LATEX_SECTION_NEW                               => OP_DOC_LATEX_SECTION . '->new';
use constant OP_DOC_LATEX_SECTION_PROCESS                           => OP_DOC_LATEX_SECTION . '->process';
use constant OP_DOC_LATEX_SECTION_SECTION_PROCESS                   => OP_DOC_LATEX_SECTION . '->sectionProcess';

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;       # Class name

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oManifest,
        $strRenderOutKey,
        $bExe
    ) =
        logDebugParam
        (
            OP_DOC_LATEX_SECTION_NEW, \@_,
            {name => 'oManifest'},
            {name => 'strRenderOutKey'},
            {name => 'bExe'}
        );

    # Create the class hash
    my $self = $class->SUPER::new('latex', $oManifest, $strRenderOutKey, $bExe);
    bless $self, $class;

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

# ####################################################################################################################################
# # variableReplace
# #
# # Replace variables in the string.
# ####################################################################################################################################
# sub variableReplace
# {
#     my $self = shift;
#     my $strBuffer = shift;
#     my $bVerbatim = shift;
#
#     if (!defined($strBuffer))
#     {
#         return undef;
#     }
#
#     foreach my $strName (sort(keys(%{$self->{var}})))
#     {
#         my $strValue = $self->{var}{$strName};
#
#         if (!defined($bVerbatim) || !$bVerbatim)
#         {
#             $strValue =~ s/\_/\\_/g;
#         }
#
#         $strBuffer =~ s/\{\[$strName\]\}/$strValue/g;
#     }
#
#     return $strBuffer;
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
    my $strOperation = logDebugParam(OP_DOC_LATEX_SECTION_PROCESS);

    # Working variables
    my $oPage = $self->{oDoc};
    my $strLatex;

    # Initialize page
    my $strTitle = "{[project]}" .
                   (defined($oPage->paramGet('title', false)) ? ' ' . $oPage->paramGet('title') : '');
    my $strSubTitle = $oPage->paramGet('subtitle', false);

    #    #
    # # Generate header
    # my $oPageHeader = $oHtmlBuilder->bodyGet()->addNew(HTML_DIV, 'page-header');
    #
    # $oPageHeader->
    #     addNew(HTML_DIV, 'page-header-title',
    #            {strContent => $strTitle});

    # Render sections
    foreach my $oSection ($oPage->nodeList('section'))
    {
        $strLatex .= (defined($strLatex) ? "\n" : '') . $self->sectionProcess($oSection, undef, 1);
    }

    # my $oPageFooter = $oHtmlBuilder->bodyGet()->
    #     addNew(HTML_DIV, 'page-footer',
    #            {strContent => ${$self->{oSite}->{oSite}}{common}{strFooter}});

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strHtml', value => $strLatex, trace => true}
    );
}

####################################################################################################################################
# sectionProcess
####################################################################################################################################
sub sectionProcess
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $strSection,
        $iDepth
    ) =
        logDebugParam
        (
            OP_DOC_LATEX_SECTION_SECTION_PROCESS, \@_,
            {name => 'oSection'},
            {name => 'strSection', required => false},
            {name => 'iDepth'}
        );

    &log(INFO, ('    ' x ($iDepth - 1)) . 'process section: ' . $oSection->paramGet('id'));

    # Create the section
    my $strSectionTitle = $self->processText($oSection->nodeGet('title')->textGet());
    $strSection .= (defined($strSection) ? ', ' : '') . "'${strSectionTitle}' " . ('Sub' x ($iDepth - 1)) . "Section";

    my $strLatex =
        "% ${strSection}\n% " . ('-' x 130) . "\n" .
        "\\" . ($iDepth > 1 ? ('sub' x ($iDepth - 1)) : '') .
        "section\{${strSectionTitle}\}\n";

    foreach my $oChild ($oSection->nodeList())
    {
        &log(INFO, ('    ' x $iDepth) . 'process child ' . $oChild->nameGet());

        # Execute a command
        if ($oChild->nameGet() eq 'execute-list')
        {
            $strLatex .=
                "\n\\begin\{lstlisting\}[title=\{" . $self->processText($oChild->nodeGet('title')->textGet()) . ":}]\n";

            foreach my $oExecute ($oChild->nodeList('execute'))
            {
                my $bExeShow = defined($oExecute->fieldGet('exe-no-show', false)) ? false : true;
                my $bExeExpectedError = defined($oExecute->fieldGet('exe-err-expect', false)) ? true : false;

                if ($bExeShow)
                {
                    my $strCommand = $oExecute->fieldGet('actual-command');

                    $strLatex .= "${strCommand}\n";

                    my $strOutput = $oExecute->fieldGet('actual-output', false);

                    if (defined($strOutput))
                    {
                        # $strLatex .=
                        #     "\\end\{lstlisting\}\n" .
                        #     "\\lstset\{title={Output:}\}\n" .
                        #     "\\begin\{lstlisting\}\n${strOutput}\n";

                        # $strOutput =~ s/^/    /smg;
                        # $strLatex .= "\nOutput:\n\n\%\\Hilight\%${strOutput}\n";
                        $strLatex .= "\nOutput:\n\n${strOutput}\n";

                        # my $strHighLight = $self->variableReplace($oExecute->fieldGet('exe-highlight', false));
                        # my $bHighLightOld;
                        # my $bHighLightFound = false;
                        # my $strHighLightOutput;
                        #
                        # foreach my $strLine (split("\n", $strOutput))
                        # {
                        #     my $bHighLight = defined($strHighLight) && $strLine =~ /$strHighLight/;
                        #
                        #     if (defined($bHighLightOld) && $bHighLight != $bHighLightOld)
                        #     {
                        #         $oExecuteBodyElement->
                        #             addNew(HTML_DIV, 'execute-body-output' . ($bHighLightOld ? '-highlight' : '') .
                        #                    ($bExeExpectedError ? '-error' : ''), {strContent => $strHighLightOutput});
                        #
                        #         undef($strHighLightOutput);
                        #     }
                        #
                        #     $strHighLightOutput .= "${strLine}\n";
                        #     $bHighLightOld = $bHighLight;
                        #
                        #     $bHighLightFound = $bHighLightFound ? true : $bHighLight ? true : false;
                        # }
                        #
                        # if (defined($bHighLightOld))
                        # {
                        #     $oExecuteBodyElement->
                        #         addNew(HTML_DIV, 'execute-body-output' . ($bHighLightOld ? '-highlight' : ''),
                        #                {strContent => $strHighLightOutput});
                        #
                        #     undef($strHighLightOutput);
                        # }
                        #
                        # if ($self->{bExe} && defined($strHighLight) && !$bHighLightFound)
                        # {
                        #     confess &log(ERROR, "unable to find a match for highlight: ${strHighLight}");
                        # }
                    }
                }
            }

            $strLatex .=
                "\\end{lstlisting}\n";
        }
        # Add code block
        elsif ($oChild->nameGet() eq 'code-block')
        {
            $strLatex .=
                "\\newline\n\\begin\{lstlisting\}\n" .
                trim($oChild->valueGet()) . "\n" .
                "\\end{lstlisting}\n";
        }
        # Add descriptive text
        elsif ($oChild->nameGet() eq 'p')
        {
            $strLatex .= "\n" . $self->processText($oChild->textGet()) . "\n";
        }
        # Add option descriptive text
        elsif ($oChild->nameGet() eq 'option-description')
        {
            my $strOption = $oChild->paramGet("key");
            my $oDescription = ${$self->{oReference}->{oConfigHash}}{&CONFIG_HELP_OPTION}{$strOption}{&CONFIG_HELP_DESCRIPTION};

            if (!defined($oDescription))
            {
                confess &log(ERROR, "unable to find ${strOption} option in sections - try adding command?");
            }

            $strLatex .= "\n" . $self->processText($oDescription) . "\n";
        }
        # Add/remove backrest config options
        elsif ($oChild->nameGet() eq 'backrest-config')
        {
            $strLatex .= $self->configProcess($oChild, $iDepth);
        }
        # Add/remove postgres config options
        elsif ($oChild->nameGet() eq 'postgres-config')
        {
            $strLatex .= $self->configProcess($oChild, $iDepth);
        }
        # Add a subsection
        elsif ($oChild->nameGet() eq 'section')
        {
            $strLatex .= "\n" . $self->sectionProcess($oChild, $strSection, $iDepth + 1);
        }
        # Skip children that have already been processed and error on others
        elsif ($oChild->nameGet() ne 'title')
        {
            confess &log(ASSERT, 'unable to find child type ' . $oChild->nameGet());
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strSection', value => $strLatex, trace => true}
    );
}

####################################################################################################################################
# configProcess
####################################################################################################################################
sub configProcess
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oConfig,
        $iDepth
    ) =
        logDebugParam
        (
            OP_DOC_LATEX_SECTION_CONFIG_PROCESS, \@_,
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Get filename
    my $strFile = $self->variableReplace($oConfig->paramGet('file'));

    &log(INFO, ('    ' x $iDepth) . 'process backrest config: ' . $strFile);

    my $strLatex =
        "\n\\begin\{lstlisting\}[title=\{" . $self->processText($oConfig->nodeGet('title')->textGet()) . " in \\textnormal\{\\texttt\{${strFile}\}\}:}]\n" .
        # "${strFile}:\n\n" .
        $oConfig->fieldGet('actual-config') .
        "\\end{lstlisting}\n";

    # foreach my $oOption ($oConfig->nodeList('backrest-config-option'))
    # {
    #     my $strSection = $oOption->fieldGet('backrest-config-option-section');
    #     my $strKey = $oOption->fieldGet('backrest-config-option-key');
    #     my $strValue = $self->variableReplace(trim($oOption->fieldGet('backrest-config-option-value'), false));
    #
    #     if (!defined($strValue))
    #     {
    #         delete(${$self->{config}}{$strFile}{$strSection}{$strKey});
    #
    #         if (keys(${$self->{config}}{$strFile}{$strSection}) == 0)
    #         {
    #             delete(${$self->{config}}{$strFile}{$strSection});
    #         }
    #
    #         &log(INFO, ('    ' x ($iDepth + 1)) . "reset ${strSection}->${strKey}");
    #     }
    #     else
    #     {
    #         ${$self->{config}}{$strFile}{$strSection}{$strKey} = $strValue;
    #         &log(INFO, ('    ' x ($iDepth + 1)) . "set ${strSection}->${strKey} = ${strValue}");
    #     }
    # }
    #
    # # Save the ini file
    # executeTest("sudo chmod 777 $strFile", {bSuppressError => true});
    # iniSave($strFile, $self->{config}{$strFile}, true);
    #
    # # Generate config element
    # my $oConfigElement = new BackRestDoc::Html::DocHtmlElement(HTML_DIV, "config");
    #
    # $oConfigElement->
    #     addNew(HTML_DIV, "config-title",
    #            {strContent => $self->processText($oConfig->nodeGet('title')->textGet()) . ':'});
    #
    # my $oConfigBodyElement = $oConfigElement->addNew(HTML_DIV, "config-body");
    #
    # $oConfigBodyElement->
    #     addNew(HTML_DIV, "config-body-title",
    #            {strContent => "${strFile}:"});
    #
    # $oConfigBodyElement->
    #     addNew(HTML_DIV, "config-body-output",
    #            {strContent => fileStringRead($strFile)});
    #
    # executeTest("sudo chown postgres:postgres $strFile");
    # executeTest("sudo chmod 640 $strFile");

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strConfig', value => $strLatex, trace => true}
    );
}

1;
