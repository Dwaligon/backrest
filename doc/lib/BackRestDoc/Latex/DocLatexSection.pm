####################################################################################################################################
# DOC LATEX SECTION MODULE
####################################################################################################################################
package BackRestDoc::Latex::DocLatexSection;

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

    # Create the class hash
    my $self = {};
    bless $self, $class;

    $self->{strClass} = $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{oSite},
        $self->{strPageId},
        $self->{bExe}
    ) =
        logDebugParam
        (
            OP_DOC_LATEX_SECTION_NEW, \@_,
            {name => 'oSite'},
            {name => 'strPageId'},
            {name => 'bExe', default => true}
        );

    # Copy page data to self
    $self->{oPage} = ${$self->{oSite}->{oSite}}{page}{$self->{strPageId}};
    $self->{oDoc} = ${$self->{oPage}}{'oDoc'};
    $self->{oRender} = ${$self->{oSite}->{oSite}}{common}{oRender};
    $self->{oReference} = ${$self->{oSite}->{oSite}}{common}{oReference};

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
    my $strTitle = ${$self->{oRender}}{strProjectName} .
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
        $strAnchor,
        $iDepth
    ) =
        logDebugParam
        (
            OP_DOC_LATEX_SECTION_SECTION_PROCESS, \@_,
            {name => 'oSection'},
            {name => 'strAnchor', required => false},
            {name => 'iDepth'}
        );

    &log(INFO, ('    ' x ($iDepth - 1)) . 'process section: ' . $oSection->paramGet('id'));

    # Working variables
    # $strAnchor = (defined($strAnchor) ? "${strAnchor}-" : '') . $oSection->paramGet('id');
    my $oRender = $self->{oRender};

    # Create the section
    my $strLatex = "\\" . ($iDepth > 1 ? ('sub' x ($iDepth - 1)) : '') .
                   "section{" . $oRender->processText($oSection->nodeGet('title')->textGet()) . '}';
    #
    # $oSectionElement->
    #     addNew(HTML_DIV, "section${iDepth}-title",
    #            {strContent => $strSectionTitle});
    #
    # my $oTocSectionTitleElement = $oSectionTocElement->
    #     addNew(HTML_DIV, "section${iDepth}-toc-title");
    #
    # $oTocSectionTitleElement->
    #     addNew(HTML_A, undef,
    #            {strContent => $strSectionTitle, strRef => "#${strAnchor}"});
    #
    # # Add the section intro if it exists
    # if (defined($oSection->textGet(false)))
    # {
    #     $oSectionElement->
    #         addNew(HTML_DIV, "section-intro",
    #                {strContent => $oRender->processText($oSection->textGet())});
    # }
    #
    # # Add the section body
    # my $oSectionBodyElement = $oSectionElement->addNew(HTML_DIV, "section-body");
    #
    # # Process each child
    # my $oSectionBodyExe;
    #
    foreach my $oChild ($oSection->nodeList())
    {
        &log(INFO, ('    ' x $iDepth) . 'process child ' . $oChild->nameGet());

        # Execute a command
        if ($oChild->nameGet() eq 'execute-list')
        {
            # my $oSectionBodyExecute = $oSectionBodyElement->addNew(HTML_DIV, "execute");
            # my $bFirst = true;
            #
            # $oSectionBodyExecute->
            #     addNew(HTML_DIV, "execute-title",
            #            {strContent => $oRender->processText($oChild->nodeGet('title')->textGet()) . ':'});
            #
            # my $oExecuteBodyElement = $oSectionBodyExecute->addNew(HTML_DIV, "execute-body");
            #
            # foreach my $oExecute ($oChild->nodeList('execute'))
            # {
            #     my $bExeShow = defined($oExecute->fieldGet('exe-no-show', false)) ? false : true;
            #     my $bExeExpectedError = defined($oExecute->fieldGet('exe-err-expect', false)) ? true : false;
            #     my ($strCommand, $strOutput) = $self->execute($oExecute, $iDepth + 1);
            #
            #     if ($bExeShow)
            #     {
            #         $oExecuteBodyElement->
            #             addNew(HTML_DIV, "execute-body-cmd" . ($bFirst ? '-first' : ''),
            #                    {strContent => $strCommand});
            #
            #         if (defined($strOutput))
            #         {
            #             my $strHighLight = $self->{oSite}->variableReplace($oExecute->fieldGet('exe-highlight', false));
            #             my $bHighLightOld;
            #             my $bHighLightFound = false;
            #             my $strHighLightOutput;
            #
            #             foreach my $strLine (split("\n", $strOutput))
            #             {
            #                 my $bHighLight = defined($strHighLight) && $strLine =~ /$strHighLight/;
            #
            #                 if (defined($bHighLightOld) && $bHighLight != $bHighLightOld)
            #                 {
            #                     $oExecuteBodyElement->
            #                         addNew(HTML_DIV, 'execute-body-output' . ($bHighLightOld ? '-highlight' : '') .
            #                                ($bExeExpectedError ? '-error' : ''), {strContent => $strHighLightOutput});
            #
            #                     undef($strHighLightOutput);
            #                 }
            #
            #                 $strHighLightOutput .= "${strLine}\n";
            #                 $bHighLightOld = $bHighLight;
            #
            #                 $bHighLightFound = $bHighLightFound ? true : $bHighLight ? true : false;
            #             }
            #
            #             if (defined($bHighLightOld))
            #             {
            #                 $oExecuteBodyElement->
            #                     addNew(HTML_DIV, 'execute-body-output' . ($bHighLightOld ? '-highlight' : ''),
            #                            {strContent => $strHighLightOutput});
            #
            #                 undef($strHighLightOutput);
            #             }
            #
            #             if ($self->{bExe} && defined($strHighLight) && !$bHighLightFound)
            #             {
            #                 confess &log(ERROR, "unable to find a match for highlight: ${strHighLight}");
            #             }
            #
            #             $bFirst = true;
            #         }
            #     }
            #
            #     $bFirst = false;
            # }
        }
        # Add code block
        elsif ($oChild->nameGet() eq 'code-block')
        {
            # $oSectionBodyElement->
            #     addNew(HTML_DIV, 'code-block',
            #            {strContent => $oChild->valueGet()});
        }
        # Add descriptive text
        elsif ($oChild->nameGet() eq 'p')
        {
            $strLatex .= "\n" . $oRender->processText($oChild->textGet()) . "\n";
        }
        # Add option descriptive text
        elsif ($oChild->nameGet() eq 'option-description')
        {
            # my $strOption = $oChild->paramGet("key");
            # my $oDescription = ${$self->{oReference}->{oConfigHash}}{&CONFIG_HELP_OPTION}{$strOption}{&CONFIG_HELP_DESCRIPTION};
            #
            # if (!defined($oDescription))
            # {
            #     confess &log(ERROR, "unable to find ${strOption} option in sections - try adding command?");
            # }
            #
            # $oSectionBodyElement->
            #     addNew(HTML_DIV, 'section-body-text',
            #            {strContent => $oRender->processText($oDescription)});
        }
        # Add/remove backrest config options
        elsif ($oChild->nameGet() eq 'backrest-config')
        {
            # $oSectionBodyElement->add($self->backrestConfigProcess($oChild, $iDepth));
        }
        # Add/remove postgres config options
        elsif ($oChild->nameGet() eq 'postgres-config')
        {
            # $oSectionBodyElement->add($self->postgresConfigProcess($oChild, $iDepth));
        }
        # Add a subsection
        elsif ($oChild->nameGet() eq 'section')
        {
            $strLatex .= "\n" . $self->sectionProcess($oChild, $strAnchor, $iDepth + 1);

            # my ($oChildSectionElement, $oChildSectionTocElement) =
            #     $self->sectionProcess($oChild, $strAnchor, $iDepth + 1);
            #
            # $oSectionBodyElement->add($oChildSectionElement);
            # $oSectionTocElement->add($oChildSectionTocElement);
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
    my $strFile = $self->{oSite}->variableReplace($oConfig->paramGet('file'));

    &log(INFO, ('    ' x $iDepth) . 'process backrest config: ' . $strFile);

    # foreach my $oOption ($oConfig->nodeList('backrest-config-option'))
    # {
    #     my $strSection = $oOption->fieldGet('backrest-config-option-section');
    #     my $strKey = $oOption->fieldGet('backrest-config-option-key');
    #     my $strValue = $self->{oSite}->variableReplace(trim($oOption->fieldGet('backrest-config-option-value'), false));
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
    #            {strContent => $self->{oRender}->processText($oConfig->nodeGet('title')->textGet()) . ':'});
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
        {name => 'strConfig', value => '', trace => true}
    );
}

1;
