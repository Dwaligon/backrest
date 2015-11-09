####################################################################################################################################
# DOC HTML PAGE MODULE
####################################################################################################################################
package BackRestDoc::Html::DocHtmlPage;
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
use BackRest::Common::Log;
use BackRest::Common::String;
use BackRest::Config::ConfigHelp;

use BackRestDoc::Common::DocManifest;
use BackRestDoc::Html::DocHtmlBuilder;
use BackRestDoc::Html::DocHtmlElement;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_DOC_HTML_PAGE                                       => 'DocHtmlPage';

use constant OP_DOC_HTML_PAGE_BACKREST_CONFIG_PROCESS               => OP_DOC_HTML_PAGE . '->backrestConfigProcess';
use constant OP_DOC_HTML_PAGE_NEW                                   => OP_DOC_HTML_PAGE . '->new';
use constant OP_DOC_HTML_PAGE_POSTGRES_CONFIG_PROCESS               => OP_DOC_HTML_PAGE . '->postgresConfigProcess';
use constant OP_DOC_HTML_PAGE_PROCESS                               => OP_DOC_HTML_PAGE . '->process';
use constant OP_DOC_HTML_PAGE_SECTION_PROCESS                       => OP_DOC_HTML_PAGE . '->sectionProcess';

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
            OP_DOC_HTML_PAGE_NEW, \@_,
            {name => 'oManifest'},
            {name => 'strRenderOutKey'},
            {name => 'bExe'}
        );

    # Create the class hash
    my $self = $class->SUPER::new(RENDER_TYPE_HTML, $oManifest, $strRenderOutKey, $bExe);
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
    my $strOperation = logDebugParam(OP_DOC_HTML_PAGE_PROCESS);

    # Working variables
    my $oPage = $self->{oDoc};

    # Initialize page
    my $strTitle = "{[project]}" .
                   (defined($oPage->paramGet('title', false)) ? ' ' . $oPage->paramGet('title') : '');
    my $strSubTitle = $oPage->paramGet('subtitle', false);

    my $oHtmlBuilder = new BackRestDoc::Html::DocHtmlBuilder("{[project]} - Reliable PostgreSQL Backup",
                                                             $strTitle . (defined($strSubTitle) ? " - ${strSubTitle}" : ''));

    # Generate header
    my $oPageHeader = $oHtmlBuilder->bodyGet()->addNew(HTML_DIV, 'page-header');

    $oPageHeader->
        addNew(HTML_DIV, 'page-header-title',
               {strContent => $strTitle});

    if (defined($strSubTitle))
    {
        $oPageHeader->
            addNew(HTML_DIV, 'page-header-subtitle',
                   {strContent => $strSubTitle});
    }

    # Generate menu
    my $oMenuBody = $oHtmlBuilder->bodyGet()->addNew(HTML_DIV, 'page-menu')->addNew(HTML_DIV, 'menu-body');

    if ($self->{strRenderOutKey} ne 'index')
    {
        my $oRenderOut = $self->{oManifest}->renderOutGet(RENDER_TYPE_HTML, 'index');

        $oMenuBody->
            addNew(HTML_DIV, 'menu')->
                addNew(HTML_A, 'menu-link', {strContent => $$oRenderOut{menu}, strRef => '{[project-url-root]}'});
    }

    foreach my $strRenderOutKey ($self->{oManifest}->renderOutList(RENDER_TYPE_HTML))
    {
        if ($strRenderOutKey ne $self->{strRenderOutKey} && $strRenderOutKey ne 'index')
        {
            my $oRenderOut = $self->{oManifest}->renderOutGet(RENDER_TYPE_HTML, $strRenderOutKey);

            $oMenuBody->
                addNew(HTML_DIV, 'menu')->
                    addNew(HTML_A, 'menu-link', {strContent => $$oRenderOut{menu}, strRef => "${strRenderOutKey}.html"});
        }
    }

    # Generate table of contents
    my $oPageTocBody;

    if (!defined($oPage->paramGet('toc', false)) || $oPage->paramGet('toc') eq 'y')
    {
        my $oPageToc = $oHtmlBuilder->bodyGet()->addNew(HTML_DIV, 'page-toc');

        $oPageToc->
            addNew(HTML_DIV, 'page-toc-title',
                   {strContent => "Table of Contents"});

        $oPageTocBody = $oPageToc->
            addNew(HTML_DIV, 'page-toc-body');
    }

    # Generate body
    my $oPageBody = $oHtmlBuilder->bodyGet()->addNew(HTML_DIV, 'page-body');

    # Render sections
    foreach my $oSection ($oPage->nodeList('section'))
    {
        my ($oChildSectionElement, $oChildSectionTocElement) =
            $self->sectionProcess($oSection, undef, 1);

        $oPageBody->add($oChildSectionElement);

        if (defined($oPageTocBody))
        {
            $oPageTocBody->add($oChildSectionTocElement);
        }
    }

    my $oPageFooter = $oHtmlBuilder->bodyGet()->
        addNew(HTML_DIV, 'page-footer',
               {strContent => '{[footer]}'});

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strHtml', value => $oHtmlBuilder->htmlGet(), trace => true}
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
            OP_DOC_HTML_PAGE_SECTION_PROCESS, \@_,
            {name => 'oSection'},
            {name => 'strAnchor', required => false},
            {name => 'iDepth'}
        );

    &log(INFO, ('    ' x ($iDepth - 1)) . 'process section: ' . $oSection->paramGet('id'));

    if ($iDepth > 3)
    {
        confess &log(ASSERT, "section depth of ${iDepth} exceeds maximum");
    }

    # Working variables
    $strAnchor = (defined($strAnchor) ? "${strAnchor}-" : '') . $oSection->paramGet('id');

    # Create the section toc element
    my $oSectionTocElement = new BackRestDoc::Html::DocHtmlElement(HTML_DIV, "section${iDepth}-toc");

    # Create the section element
    my $oSectionElement = new BackRestDoc::Html::DocHtmlElement(HTML_DIV, "section${iDepth}");

    # Add the section anchor
    $oSectionElement->addNew(HTML_A, undef, {strId => $strAnchor});

    # Add the section title to section and toc
    my $strSectionTitle = $self->processText($oSection->nodeGet('title')->textGet());

    $oSectionElement->
        addNew(HTML_DIV, "section${iDepth}-title",
               {strContent => $strSectionTitle});

    my $oTocSectionTitleElement = $oSectionTocElement->
        addNew(HTML_DIV, "section${iDepth}-toc-title");

    $oTocSectionTitleElement->
        addNew(HTML_A, undef,
               {strContent => $strSectionTitle, strRef => "#${strAnchor}"});

    # Add the section intro if it exists
    if (defined($oSection->textGet(false)))
    {
        $oSectionElement->
            addNew(HTML_DIV, "section-intro",
                   {strContent => $self->processText($oSection->textGet())});
    }

    # Add the section body
    my $oSectionBodyElement = $oSectionElement->addNew(HTML_DIV, "section-body");

    # Process each child
    my $oSectionBodyExe;

    foreach my $oChild ($oSection->nodeList())
    {
        &log(INFO, ('    ' x $iDepth) . 'process child ' . $oChild->nameGet());

        # Execute a command
        if ($oChild->nameGet() eq 'execute-list')
        {
            my $oSectionBodyExecute = $oSectionBodyElement->addNew(HTML_DIV, "execute");
            my $bFirst = true;

            $oSectionBodyExecute->
                addNew(HTML_DIV, "execute-title",
                       {strContent => $self->processText($oChild->nodeGet('title')->textGet()) . ':'});

            my $oExecuteBodyElement = $oSectionBodyExecute->addNew(HTML_DIV, "execute-body");

            foreach my $oExecute ($oChild->nodeList('execute'))
            {
                my $bExeShow = defined($oExecute->fieldGet('exe-no-show', false)) ? false : true;
                my $bExeExpectedError = defined($oExecute->fieldGet('exe-err-expect', false)) ? true : false;

                my ($strCommand, $strOutput) = $self->execute($oExecute, $iDepth + 1);

                if ($bExeShow)
                {
                    $oExecute->fieldSet('actual-command', $strCommand);

                    $oExecuteBodyElement->
                        addNew(HTML_DIV, "execute-body-cmd" . ($bFirst ? '-first' : ''),
                               {strContent => $strCommand});

                    if (defined($strOutput))
                    {
                        my $strHighLight = $self->{oManifest}->variableReplace($oExecute->fieldGet('exe-highlight', false));
                        my $bHighLightOld;
                        my $bHighLightFound = false;
                        my $strHighLightOutput;

                        $oExecute->fieldSet('actual-output', $strOutput);

                        foreach my $strLine (split("\n", $strOutput))
                        {
                            my $bHighLight = defined($strHighLight) && $strLine =~ /$strHighLight/;

                            if (defined($bHighLightOld) && $bHighLight != $bHighLightOld)
                            {
                                $oExecuteBodyElement->
                                    addNew(HTML_DIV, 'execute-body-output' . ($bHighLightOld ? '-highlight' : '') .
                                           ($bExeExpectedError ? '-error' : ''), {strContent => $strHighLightOutput});

                                undef($strHighLightOutput);
                            }

                            $strHighLightOutput .= "${strLine}\n";
                            $bHighLightOld = $bHighLight;

                            $bHighLightFound = $bHighLightFound ? true : $bHighLight ? true : false;
                        }

                        if (defined($bHighLightOld))
                        {
                            $oExecuteBodyElement->
                                addNew(HTML_DIV, 'execute-body-output' . ($bHighLightOld ? '-highlight' : ''),
                                       {strContent => $strHighLightOutput});

                            undef($strHighLightOutput);
                        }

                        if ($self->{bExe} && defined($strHighLight) && !$bHighLightFound)
                        {
                            confess &log(ERROR, "unable to find a match for highlight: ${strHighLight}");
                        }

                        $bFirst = true;
                    }
                }

                $bFirst = false;
            }
        }
        # Add code block
        elsif ($oChild->nameGet() eq 'code-block')
        {
            $oSectionBodyElement->
                addNew(HTML_DIV, 'code-block',
                       {strContent => $oChild->valueGet()});
        }
        # Add descriptive text
        elsif ($oChild->nameGet() eq 'p')
        {
            $oSectionBodyElement->
                addNew(HTML_DIV, 'section-body-text',
                       {strContent => $self->processText($oChild->textGet())});
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

            $oSectionBodyElement->
                addNew(HTML_DIV, 'section-body-text',
                       {strContent => $self->processText($oDescription)});
        }
        # Add/remove backrest config options
        elsif ($oChild->nameGet() eq 'backrest-config')
        {
            $oSectionBodyElement->add($self->backrestConfigProcess($oChild, $iDepth));
        }
        # Add/remove postgres config options
        elsif ($oChild->nameGet() eq 'postgres-config')
        {
            $oSectionBodyElement->add($self->postgresConfigProcess($oChild, $iDepth));
        }
        # Add a subsection
        elsif ($oChild->nameGet() eq 'section')
        {
            my ($oChildSectionElement, $oChildSectionTocElement) =
                $self->sectionProcess($oChild, $strAnchor, $iDepth + 1);

            $oSectionBodyElement->add($oChildSectionElement);
            $oSectionTocElement->add($oChildSectionTocElement);
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
        {name => 'oSectionElement', value => $oSectionElement, trace => true},
        {name => 'oSectionTocElement', value => $oSectionTocElement, trace => true}
    );
}

####################################################################################################################################
# backrestConfigProcess
####################################################################################################################################
sub backrestConfigProcess
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
            OP_DOC_HTML_PAGE_BACKREST_CONFIG_PROCESS, \@_,
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    my ($strFile, $strConfig) = $self->backrestConfig($oConfig, $iDepth);

    # Generate config element
    my $oConfigElement = new BackRestDoc::Html::DocHtmlElement(HTML_DIV, "config");

    $oConfigElement->
        addNew(HTML_DIV, "config-title",
               {strContent => $self->processText($oConfig->nodeGet('title')->textGet()) . ':'});

    my $oConfigBodyElement = $oConfigElement->addNew(HTML_DIV, "config-body");

    $oConfigBodyElement->
        addNew(HTML_DIV, "config-body-title",
               {strContent => "${strFile}:"});

    $oConfigBodyElement->
        addNew(HTML_DIV, "config-body-output",
               {strContent => $strConfig});

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oConfigElement', value => $oConfigElement, trace => true}
    );
}

####################################################################################################################################
# postgresConfigProcess
####################################################################################################################################
sub postgresConfigProcess
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
            OP_DOC_HTML_PAGE_POSTGRES_CONFIG_PROCESS, \@_,
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    my ($strFile, $strConfig) = $self->postgresConfig($oConfig, $iDepth);

    # Generate config element
    my $oConfigElement = new BackRestDoc::Html::DocHtmlElement(HTML_DIV, "config");

    $oConfigElement->
        addNew(HTML_DIV, "config-title",
               {strContent => $self->processText($oConfig->nodeGet('title')->textGet()) . ':'});

    my $oConfigBodyElement = $oConfigElement->addNew(HTML_DIV, "config-body");

    $oConfigBodyElement->
        addNew(HTML_DIV, "config-body-title",
               {strContent => "append to ${strFile}:"});

    $oConfigBodyElement->
        addNew(HTML_DIV, "config-body-output",
               {strContent => defined($strConfig) ? $strConfig : '<No PgBackRest Settings>'});

    $oConfig->fieldSet('actual-config', $strConfig);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oConfigElement', value => $oConfigElement, trace => true}
    );
}

1;
