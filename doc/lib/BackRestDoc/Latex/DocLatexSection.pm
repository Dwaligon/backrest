####################################################################################################################################
# DOC LATEX SECTION MODULE
####################################################################################################################################
package BackRestDoc::Latex::DocLatexSection;
use parent 'BackRestDoc::Common::DocExecute';

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

    # Render sections
    foreach my $oSection ($oPage->nodeList('section'))
    {
        $strLatex .= (defined($strLatex) ? "\n" : '') . $self->sectionProcess($oSection, undef, 1);
    }

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

    &log($iDepth == 1 ? INFO : DEBUG, ('    ' x ($iDepth + 1)) . 'process section: ' . $oSection->paramGet('id'));

    # Create the section
    my $strSectionTitle = $self->processText($oSection->nodeGet('title')->textGet());
    $strSection .= (defined($strSection) ? ', ' : '') . "'${strSectionTitle}' " . ('Sub' x ($iDepth - 1)) . "Section";

    my $strLatex =
        "% ${strSection}\n% " . ('-' x 130) . "\n\\";

    if ($iDepth <= 3)
    {
        $strLatex .= ($iDepth > 1 ? ('sub' x ($iDepth - 1)) : '') . "section";
    }
    elsif ($iDepth == 4)
    {
        $strLatex .= 'paragraph';
    }
    else
    {
        confess &log(ASSERT, "section depth of ${iDepth} exceeds maximum");
    }

    $strLatex .= "\{${strSectionTitle}\}\n";

    foreach my $oChild ($oSection->nodeList())
    {
        &log(DEBUG, ('    ' x ($iDepth + 2)) . 'process child ' . $oChild->nameGet());

        # Execute a command
        if ($oChild->nameGet() eq 'execute-list')
        {
            $strLatex .=
                "\n\\begin\{lstlisting\}[title=\{" . $self->processText($oChild->nodeGet('title')->textGet()) . ":}]\n";

            foreach my $oExecute ($oChild->nodeList('execute'))
            {
                my $bExeShow = defined($oExecute->fieldGet('exe-no-show', false)) ? false : true;
                my $bExeExpectedError = defined($oExecute->fieldGet('exe-err-expect', false)) ? true : false;
                my ($strCommand, $strOutput) = $self->execute($oExecute, $iDepth + 3);

                if ($bExeShow)
                {
                    $strLatex .= "${strCommand}\n";

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
        # Add table
        elsif ($oChild->nameGet() eq 'table')
        {
            my $oHeader = $oChild->nodeGet('table-header');
            my @oyColumn = $oHeader->nodeList('table-column');

            my $strWidth = '{' . ($oHeader->paramTest('width') ? $oHeader->paramGet('width') : '\textwidth') . '}';

            # Build the table header
            $strLatex .= "\\vspace{1em}\\newline\n";

            $strLatex .= "\\begin{tabularx}${strWidth}{ | ";

            foreach my $oColumn (@oyColumn)
            {
                my $strAlignCode;
                my $strAlign = $oColumn->paramGet("align", false);

                if ($oColumn->paramTest('fill', 'y'))
                {
                    if (!defined($strAlign) || $strAlign eq 'left')
                    {
                        $strAlignCode = 'X';
                    }
                    elsif ($strAlign eq 'right')
                    {
                        $strAlignCode = 'R';
                    }
                    else
                    {
                        confess &log(ERROR, "align '${strAlign}' not valid when fill=y");
                    }
                }
                else
                {
                    if (!defined($strAlign) || $strAlign eq 'left')
                    {
                        $strAlignCode = 'l';
                    }
                    elsif ($strAlign eq 'center')
                    {
                        $strAlignCode = 'c';
                    }
                    elsif ($strAlign eq 'right')
                    {
                        $strAlignCode = 'r';
                    }
                    else
                    {
                        confess &log(ERROR, "align '${strAlign}' not valid");
                    }
                }

                # $strLatex .= 'p{' . $oColumn->paramGet("width") . '} | ';
                $strLatex .= $strAlignCode . ' | ';
            }

            $strLatex .= "}\n";

            if ($oChild->nodeGet("title", false))
            {
                $strLatex .= "\\caption{" . $self->processText($oChild->nodeGet("title")->textGet()) . ":}\\\\\n";
            }

            # $strLatex .= "\\begin{tabulary}{\\textwidth}{LLLL}\n\\toprule\n";
            $strLatex .= "\\hline\n";

            my $strLine;

            foreach my $oColumn (@oyColumn)
            {
                $strLine .= (defined($strLine) ? ' & ' : '') . '\textbf{' . $self->processText($oColumn->textGet()) . '}';
            }

            $strLatex .= "${strLine}\\\\";

            # Build the rows
            foreach my $oRow ($oChild->nodeGet('table-data')->nodeList('table-row'))
            {
                $strLatex .= "\\hline\n";
                undef($strLine);

                foreach my $oRowCell ($oRow->nodeList('table-cell'))
                {
                    $strLine .= (defined($strLine) ? ' & ' : '') . $self->processText($oRowCell->textGet());
                }

                $strLatex .= "${strLine}\\\\";
            }

            $strLatex .= "\\hline\n\\end{tabularx}\n";
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
        # Add/remove config options
        elsif ($oChild->nameGet() eq 'backrest-config' || $oChild->nameGet() eq 'postgres-config')
        {
            $strLatex .= $self->configProcess($oChild, $iDepth + 3);
        }
        # Add a subsection
        elsif ($oChild->nameGet() eq 'section')
        {
            $strLatex .= "\n" . $self->sectionProcess($oChild, $strSection, $iDepth + 1);
        }
        # Skip children that have already been processed and error on others
        elsif ($oChild->nameGet() ne 'title')
        {
            confess &log(ASSERT, 'unable to process child type ' . $oChild->nameGet());
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

    # Working variables
    my $strFile;
    my $strConfig;

    # Generate the config
    if ($oConfig->nameGet() eq 'backrest-config')
    {
        ($strFile, $strConfig) = $self->backrestConfig($oConfig, $iDepth);
    }
    else
    {
        ($strFile, $strConfig) = $self->postgresConfig($oConfig, $iDepth);
    }

    # Replace _ in filename
    $strFile = $self->variableReplace($strFile);
    # $strFile = $self->variableReplace($strFile);

    # Render the config
    my $strLatex =
        "\n\\begin\{lstlisting\}[title=\{" . $self->processText($oConfig->nodeGet('title')->textGet()) .
            " in \\textnormal\{\\texttt\{${strFile}\}\}:}]\n" .
        ${strConfig} .
        "\\end{lstlisting}\n";

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strConfig', value => $strLatex, trace => true}
    );
}

1;
