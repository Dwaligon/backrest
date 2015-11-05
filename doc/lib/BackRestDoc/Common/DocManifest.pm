####################################################################################################################################
# DOC MANIFEST MODULE
####################################################################################################################################
package BackRestDoc::Common::DocManifest;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Cwd qw(abs_path);
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
use constant RENDER_TYPE_PDF                                        => 'pdf';

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
        my $strKey = $oSource->paramGet('key');
        &log(INFO, "    loading source ${strKey}");

        ${$self->{oManifest}}{source}{$strKey}{oDoc} = new BackRestDoc::Common::Doc("$self->{strBasePath}/xml/${strKey}.xml");
    }

    # Iterate the renderers
    foreach my $oRender ($self->{oManifestXml}->nodeGet('render-list')->nodeList('render'))
    {
        my $strType = $oRender->paramGet(RENDER_TYPE);

        logDebugMisc
        (
            $strOperation, '    load render',
            {name => 'strType', value => $strType}
        );

        # Only one instance of each render type can be defined
        if (defined(${$self->{oManifest}}{&RENDER}{$strType}))
        {
            confess &log(ERROR, "render ${strType} has already been defined");
        }

        # Get the filename if this is a pdf
        ${$self->{oManifest}}{render}{$strType}{file} = $oRender->paramGet(RENDER_FILE, false);

        if (defined(${$self->{oManifest}}{render}{$strType}{file}) && $strType ne RENDER_TYPE_PDF)
        {
            confess &log(ERROR, 'only the pdf render type can have file set')
        }

        # Iterate the render sources
        foreach my $oRenderSource ($oRender->nodeList('render-source'))
        {
            my $strKey = $oRenderSource->paramGet('key');
            my $strSource = $oRenderSource->paramGet('source', false, $strKey);

            ${$self->{oManifest}}{render}{$strType}{$strKey}{source} = $strSource;

            my $oRenderSourceHash = ${$self->{oManifest}}{render}{$strType}{$strKey};

            # Get the filename if this is a pdf
            $${oRenderSourceHash}{menu} = $oRenderSource->paramGet('menu', false);

            if (defined($${oRenderSourceHash}{menu}) && $strType ne RENDER_TYPE_HTML)
            {
                confess &log(ERROR, 'only the html render type can have menu set')
            }

            logDebugMisc
            (
                $strOperation, '        load render source',
                {name => 'strKey', value => $strKey},
                {name => 'strSource', value => $strSource},
                {name => 'strMenu', value => $${oRenderSourceHash}{menu}}
            );
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# sourceGet
####################################################################################################################################
sub sourceGet
{
    my $class = shift;       # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    my (
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

1;
