####################################################################################################################################
# REMOTE MODULE
####################################################################################################################################
package BackRest::Remote;
use parent 'BackRest::Protocol';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use File::Basename qw(dirname);

use lib dirname($0) . '/../lib';
use BackRest::Archive;
use BackRest::Config;
use BackRest::Db;
use BackRest::Exception;
use BackRest::File;
use BackRest::Info;
use BackRest::Protocol;
use BackRest::Utility;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_REMOTE                                              => 'Remote';

use constant OP_REMOTE_NEW                                          => OP_REMOTE . "->new";

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;                  # Class name
    my $strHost = shift;                # Host to connect to for remote (optional as this can also be used on the remote)
    my $strUser = shift;                # User to connect to for remote (must be set if strHost is set)
    my $strCommand = shift;             # Command to execute on remote ('remote' if this is the remote)
    my $iBlockSize = shift;             # Buffer size
    my $iCompressLevel = shift;         # Set compression level
    my $iCompressLevelNetwork = shift;  # Set compression level for network only compression

    # Debug
    logDebug(OP_REMOTE_NEW, DEBUG_CALL, undef,
             {host => $strHost, user => $strUser, command => $strCommand},
             defined($strHost) ? DEBUG : TRACE);

    # Init object and store variables
    my $self = $class->SUPER::new(CMD_REMOTE, !defined($strHost), $strCommand, $iBlockSize, $iCompressLevel, $iCompressLevelNetwork,
                                  $strHost, $strUser);

    return $self;
}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # Create the file object
    my $oFile = new BackRest::File
    (
        optionGet(OPTION_STANZA, false),
        optionGet(OPTION_REPO_REMOTE_PATH, false),
        undef,
        $self,
    );

    # Create objects
    my $oArchive = new BackRest::Archive();
    my $oInfo = new BackRest::Info();
    my $oJSON = JSON::PP->new();
    my $oDb = new BackRest::Db(false);

    # Command string
    my $strCommand = OP_NOOP;

    # Loop until the exit command is received
    while ($strCommand ne OP_EXIT)
    {
        my %oParamHash;

        $strCommand = $self->command_read(\%oParamHash);

        eval
        {
            # Copy file
            if ($strCommand eq OP_FILE_COPY ||
                $strCommand eq OP_FILE_COPY_IN ||
                $strCommand eq OP_FILE_COPY_OUT)
            {
                my $bResult;
                my $strChecksum;
                my $iFileSize;

                # Copy a file locally
                if ($strCommand eq OP_FILE_COPY)
                {
                    ($bResult, $strChecksum, $iFileSize) =
                        $oFile->copy(PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'source_file'),
                                     PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'destination_file'),
                                     $self->paramGet(\%oParamHash, 'source_compressed'),
                                     $self->paramGet(\%oParamHash, 'destination_compress'),
                                     $self->paramGet(\%oParamHash, 'ignore_missing_source', false),
                                     undef,
                                     $self->paramGet(\%oParamHash, 'mode', false),
                                     $self->paramGet(\%oParamHash, 'destination_path_create') ? 'Y' : 'N',
                                     $self->paramGet(\%oParamHash, 'user', false),
                                     $self->paramGet(\%oParamHash, 'group', false),
                                     $self->paramGet(\%oParamHash, 'append_checksum', false));
                }
                # Copy a file from STDIN
                elsif ($strCommand eq OP_FILE_COPY_IN)
                {
                    ($bResult, $strChecksum, $iFileSize) =
                        $oFile->copy(PIPE_STDIN, undef,
                                     PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'destination_file'),
                                     $self->paramGet(\%oParamHash, 'source_compressed'),
                                     $self->paramGet(\%oParamHash, 'destination_compress'),
                                     undef, undef,
                                     $self->paramGet(\%oParamHash, 'mode', false),
                                     $self->paramGet(\%oParamHash, 'destination_path_create'),
                                     $self->paramGet(\%oParamHash, 'user', false),
                                     $self->paramGet(\%oParamHash, 'group', false),
                                     $self->paramGet(\%oParamHash, 'append_checksum', false));
                }
                # Copy a file to STDOUT
                elsif ($strCommand eq OP_FILE_COPY_OUT)
                {
                    ($bResult, $strChecksum, $iFileSize) =
                        $oFile->copy(PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'source_file'),
                                     PIPE_STDOUT, undef,
                                     $self->paramGet(\%oParamHash, 'source_compressed'),
                                     $self->paramGet(\%oParamHash, 'destination_compress'));
                }

                $self->output_write(($bResult ? 'Y' : 'N') . " " . (defined($strChecksum) ? $strChecksum : '?') . " " .
                                    (defined($iFileSize) ? $iFileSize : '?'));
            }
            # List files in a path
            elsif ($strCommand eq OP_FILE_LIST)
            {
                my $strOutput;

                foreach my $strFile ($oFile->list(PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'path'),
                                                  $self->paramGet(\%oParamHash, 'expression', false),
                                                  $self->paramGet(\%oParamHash, 'sort_order'),
                                                  $self->paramGet(\%oParamHash, 'ignore_missing')))
                {
                    if (defined($strOutput))
                    {
                        $strOutput .= "\n";
                    }

                    $strOutput .= $strFile;
                }

                $self->output_write($strOutput);
            }
            # Create a path
            elsif ($strCommand eq OP_FILE_PATH_CREATE)
            {
                $oFile->path_create(PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'path'),
                                    $self->paramGet(\%oParamHash, 'mode', false));
                $self->output_write();
            }
            # Check if a file/path exists
            elsif ($strCommand eq OP_FILE_EXISTS)
            {
                $self->output_write($oFile->exists(PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'path')) ? 'Y' : 'N');
            }
            # Wait
            elsif ($strCommand eq OP_FILE_WAIT)
            {
                $self->output_write($oFile->wait(PATH_ABSOLUTE));
            }
            # Generate a manifest
            elsif ($strCommand eq OP_FILE_MANIFEST)
            {
                my %oManifestHash;

                $oFile->manifest(PATH_ABSOLUTE, $self->paramGet(\%oParamHash, 'path'), \%oManifestHash);

                my $strOutput = "name\ttype\tuser\tgroup\tmode\tmodification_time\tinode\tsize\tlink_destination";

                foreach my $strName (sort(keys $oManifestHash{name}))
                {
                    $strOutput .= "\n${strName}\t" .
                        $oManifestHash{name}{"${strName}"}{type} . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{user}) ? $oManifestHash{name}{"${strName}"}{user} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{group}) ? $oManifestHash{name}{"${strName}"}{group} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{mode}) ? $oManifestHash{name}{"${strName}"}{mode} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{modification_time}) ?
                            $oManifestHash{name}{"${strName}"}{modification_time} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{inode}) ? $oManifestHash{name}{"${strName}"}{inode} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{size}) ? $oManifestHash{name}{"${strName}"}{size} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{link_destination}) ?
                            $oManifestHash{name}{"${strName}"}{link_destination} : "");
                }

                $self->output_write($strOutput);
            }
            # Archive push checks
            elsif ($strCommand eq OP_ARCHIVE_PUSH_CHECK)
            {
                my ($strArchiveId, $strChecksum) = $oArchive->pushCheck($oFile,
                                                                        $self->paramGet(\%oParamHash, 'wal-segment'),
                                                                        undef,
                                                                        $self->paramGet(\%oParamHash, 'db-version'),
                                                                        $self->paramGet(\%oParamHash, 'db-sys-id'));

                $self->output_write("${strArchiveId}\t" . (defined($strChecksum) ? $strChecksum : 'Y'));
            }
            elsif ($strCommand eq OP_ARCHIVE_GET_CHECK)
            {
                $self->output_write($oArchive->getCheck($oFile));
            }
            # Info list stanza
            elsif ($strCommand eq OP_INFO_LIST_STANZA)
            {
                $self->output_write(
                    $oJSON->encode(
                        $oInfo->listStanza($oFile, $self->paramGet(\%oParamHash, 'stanza', false))));
            }
            elsif ($strCommand eq OP_DB_INFO)
            {
                my ($strDbVersion, $iControlVersion, $iCatalogVersion, $ullDbSysId) =
                    $oDb->info($oFile, $self->paramGet(\%oParamHash, 'db-path'));

                $self->output_write("${strDbVersion}\t${iControlVersion}\t${iCatalogVersion}\t${ullDbSysId}");
            }
            # Continue if noop or exit
            elsif ($strCommand ne OP_NOOP && $strCommand ne OP_EXIT)
            {
                confess "invalid command: ${strCommand}";
            }
        };

        # Process errors
        if ($@)
        {
            $self->error_write($@);
        }
    }
}

1;
