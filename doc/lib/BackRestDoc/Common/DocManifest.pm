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

####################################################################################################################################
# File constants
####################################################################################################################################
use constant FILE_MANIFEST                                          => 'manifest.xml';

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
    $self->{oManifest} = new BackRestDoc::Common::Doc("$self->{strBasePath}/manifest.xml");

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

1;
