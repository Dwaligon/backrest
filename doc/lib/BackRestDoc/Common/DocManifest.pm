####################################################################################################################################
# DOC MANIFEST MODULE
####################################################################################################################################
package BackRestDoc::Common::DocManifest;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Cwd qw(abs_path);
use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);
use Scalar::Util qw(blessed);

use lib dirname($0) . '/../lib';
use BackRest::Common::Log;
use BackRest::Common::String;
use BackRest::FileCommon;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_DOC_MANIFEST                                        => 'DocManifest';

use constant OP_DOC_MANIFEST_NEW                                    => OP_DOC_MANIFEST . '->new';
use constant OP_DOC_MANIFEST_RENDER_OUT_GET                         => OP_DOC_MANIFEST . '->renderOutGet';
use constant OP_DOC_MANIFEST_RENDER_OUT_LIST                        => OP_DOC_MANIFEST . '->renderOutList';
use constant OP_DOC_MANIFEST_SOURCE_GET                             => OP_DOC_MANIFEST . '->sourceGet';

####################################################################################################################################
# File constants
####################################################################################################################################
use constant FILE_MANIFEST                                          => 'manifest.xml';

####################################################################################################################################
# Render constants
####################################################################################################################################
use constant RENDER                                                 => 'render';
use constant RENDER_FILE                                            => 'file';

use constant RENDER_TYPE                                            => 'type';
use constant RENDER_TYPE_HTML                                       => 'html';
    push @EXPORT, qw(RENDER_TYPE_HTML);
use constant RENDER_TYPE_PDF                                        => 'pdf';
    push @EXPORT, qw(RENDER_TYPE_PDF);

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;       # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{strBasePath}
    ) =
        logDebugParam
        (
            OP_DOC_MANIFEST_NEW, \@_,
            {name => 'strBasePath', required => false}
        );

    # Set the base path if it was not passed in
    if (!defined($self->{strBasePath}))
    {
        $self->{strBasePath} = abs_path(dirname($0));
    }

    # Load the manifest
    $self->{oManifestXml} = new BackRestDoc::Common::Doc("$self->{strBasePath}/manifest.xml");

    # Iterate the sources
    $self->{oManifest} = {};

    foreach my $oSource ($self->{oManifestXml}->nodeGet('source-list')->nodeList('source'))
    {
        my $oSourceHash = {};
        my $strKey = $oSource->paramGet('key');

        logDebugMisc
        (
            $strOperation, 'load source',
            {name => 'strKey', value => $strKey}
        );

        $$oSourceHash{doc} = new BackRestDoc::Common::Doc("$self->{strBasePath}/xml/${strKey}.xml");

        # Read variables from source
        if (defined($$oSourceHash{doc}->nodeGet('variable-list', false)))
        {
            foreach my $oVariable ($$oSourceHash{doc}->nodeGet('variable-list')->nodeList('variable'))
            {
                my $strKey = $oVariable->fieldGet('variable-name');
                my $strValue = $oVariable->fieldGet('variable-value');

                $self->variableSet($strKey, $strValue);

                logDebugMisc
                (
                    $strOperation, '    load source variable',
                    {name => 'strKey', value => $strKey},
                    {name => 'strValue', value => $strValue}
                );
            }
        }

        ${$self->{oManifest}}{source}{$strKey} = $oSourceHash;
    }

    # Iterate the renderers
    foreach my $oRender ($self->{oManifestXml}->nodeGet('render-list')->nodeList('render'))
    {
        my $oRenderHash = {};
        my $strType = $oRender->paramGet(RENDER_TYPE);

        # Only one instance of each render type can be defined
        if (defined(${$self->{oManifest}}{&RENDER}{$strType}))
        {
            confess &log(ERROR, "render ${strType} has already been defined");
        }

        # Get the file param
        $${oRenderHash}{file} = $oRender->paramGet(RENDER_FILE, false);

        logDebugMisc
        (
            $strOperation, '    load render',
            {name => 'strType', value => $strType},
            {name => 'strFile', value => $${oRenderHash}{file}}
        );

        # Error if file is set and render type is not pdf
        if (defined($${oRenderHash}{file}) && $strType ne RENDER_TYPE_PDF)
        {
            confess &log(ERROR, 'only the pdf render type can have file set')
        }

        # Iterate the render sources
        foreach my $oRenderOut ($oRender->nodeList('render-source'))
        {
            my $oRenderOutHash = {};
            my $strKey = $oRenderOut->paramGet('key');
            my $strSource = $oRenderOut->paramGet('source', false, $strKey);

            $$oRenderOutHash{source} = $strSource;

            # Get the filename if this is a pdf
            $$oRenderOutHash{menu} = $oRenderOut->paramGet('menu', false);

            if (defined($$oRenderOutHash{menu}) && $strType ne RENDER_TYPE_HTML)
            {
                confess &log(ERROR, 'only the html render type can have menu set')
            }

            logDebugMisc
            (
                $strOperation, '        load render source',
                {name => 'strKey', value => $strKey},
                {name => 'strSource', value => $strSource},
                {name => 'strMenu', value => $${oRenderOutHash}{menu}}
            );

            $${oRenderHash}{out}{$strKey} = $oRenderOutHash;
        }

        ${$self->{oManifest}}{render}{$strType} = $oRenderHash;
    }

    # Read variables from manifest
    if (defined($self->{oManifestXml}->nodeGet('variable-list', false)))
    {
        foreach my $oVariable ($self->{oManifestXml}->nodeGet('variable-list')->nodeList('variable'))
        {
            my $strKey = $oVariable->paramGet('key');
            my $strValue = $oVariable->valueGet();

            $self->variableSet($strKey, $strValue);

                logDebugMisc
                (
                    $strOperation, '    load manifest variable',
                    {name => 'strKey', value => $strKey},
                    {name => 'strValue', value => $strValue}
                );
        }
    }

    # use Data::Dumper; confess Dumper($self->{oVariable});

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
    my $strType = shift;

    if (!defined($strBuffer))
    {
        return undef;
    }

    foreach my $strName (sort(keys(%{$self->{oVariable}})))
    {
        my $strValue = $self->{oVariable}{$strName};

        if (defined($strType) && $strType eq 'latex')
        {
            $strValue =~ s/\_/\\_/g;
        }

        $strBuffer =~ s/\{\[$strName\]\}/$strValue/g;
    }

    return $strBuffer;
}

####################################################################################################################################
# variableSet
#
# Set a variable to be replaced later.
####################################################################################################################################
sub variableSet
{
    my $self = shift;
    my $strKey = shift;
    my $strValue = shift;

    if (defined(${$self->{oVariable}}{$strKey}))
    {
        confess &log(ERROR, "${strKey} variable is already defined");
    }

    ${$self->{oVariable}}{$strKey} = $self->variableReplace($strValue);
}

####################################################################################################################################
# variableGet
#
# Get the current value of a variable.
####################################################################################################################################
sub variableGet
{
    my $self = shift;
    my $strKey = shift;

    return ${$self->{oVariable}}{$strKey};
}

####################################################################################################################################
# sourceGet
####################################################################################################################################
sub sourceGet
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strSource
    ) =
        logDebugParam
        (
            OP_DOC_MANIFEST_SOURCE_GET, \@_,
            {name => 'strSource', trace => true}
        );

    if (!defined(${$self->{oManifest}}{source}{$strSource}))
    {
        confess &log(ERROR, "source ${strSource} does not exist");
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oSource', value => ${$self->{oManifest}}{source}{$strSource}}
    );
}

####################################################################################################################################
# renderOutList
####################################################################################################################################
sub renderOutList
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType
    ) =
        logDebugParam
        (
            OP_DOC_MANIFEST_RENDER_OUT_LIST, \@_,
            {name => 'strType'}
        );

    my @stryRenderOut;

    if (defined(${$self->{oManifest}}{render}{$strType}))
    {
        @stryRenderOut = sort(keys(${$self->{oManifest}}{render}{$strType}{out}));
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'stryRenderOut', value => \@stryRenderOut}
    );
}

####################################################################################################################################
# renderOutGet
####################################################################################################################################
sub renderOutGet
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType,
        $strKey
    ) =
        logDebugParam
        (
            OP_DOC_MANIFEST_RENDER_OUT_GET, \@_,
            {name => 'strType', trace => true},
            {name => 'strKey', trace => true}
        );

    # use Data::Dumper; print Dumper(${$self->{oManifest}}{render});

    if (!defined(${$self->{oManifest}}{render}{$strType}{out}{$strKey}))
    {
        confess &log(ERROR, "render out ${strKey} does not exist");
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oRenderOut', value => ${$self->{oManifest}}{render}{$strType}{out}{$strKey}}
    );
}

1;
