####################################################################################################################################
# RESTORE MODULE
####################################################################################################################################
package BackRest::Restore;

use threads;
use threads::shared;
use Thread::Queue;
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use File::Basename qw(dirname);
use File::stat qw(lstat);
use File::Path qw(remove_tree);

use lib dirname($0);
use BackRest::Exception;
use BackRest::Utility;
use BackRest::Lock;
use BackRest::ThreadGroup;
use BackRest::RestoreFile;
use BackRest::Config;
use BackRest::Manifest;
use BackRest::File;
use BackRest::Db;

####################################################################################################################################
# Recovery.conf file
####################################################################################################################################
use constant FILE_RECOVERY_CONF  => 'recovery.conf';

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;              # Class name
    my $strDbClusterPath = shift;   # Database cluster path
    my $strBackupPath = shift;      # Backup to restore
    my $oRemapRef = shift;          # Tablespace remaps
    my $oFile = shift;              # Default file object
    my $iThreadTotal = shift;       # Total threads to run for restore
    my $bDelta = shift;             # perform delta restore
    my $bForce = shift;             # force a restore
    my $strType = shift;            # Recovery type
    my $strTarget = shift;          # Recovery target
    my $bTargetExclusive = shift;   # Target exlusive option
    my $bTargetResume = shift;      # Target resume option
    my $strTargetTimeline = shift;  # Target timeline option
    my $oRecoveryRef = shift;       # Other recovery options
    my $strStanza = shift;          # Restore stanza
    my $strBackRestBin = shift;     # Absolute backrest filename
    my $strConfigFile = shift;      # Absolute config filename (optional)

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Initialize variables
    $self->{strDbClusterPath} = $strDbClusterPath;
    $self->{strBackupPath} = $strBackupPath;
    $self->{oRemapRef} = $oRemapRef;
    $self->{oFile} = $oFile;
    $self->{iThreadTotal} = defined($iThreadTotal) ? $iThreadTotal : 1;
    $self->{bDelta} = $bDelta;
    $self->{bForce} = $bForce;
    $self->{strType} = $strType;
    $self->{strTarget} = $strTarget;
    $self->{bTargetExclusive} = $bTargetExclusive;
    $self->{bTargetResume} = $bTargetResume;
    $self->{strTargetTimeline} = $strTargetTimeline;
    $self->{oRecoveryRef} = $oRecoveryRef;
    $self->{strStanza} = $strStanza;
    $self->{strBackRestBin} = $strBackRestBin;
    $self->{strConfigFile} = $strConfigFile;

    return $self;
}

####################################################################################################################################
# MANIFEST_OWNERSHIP_CHECK
#
# Checks the users and groups that exist in the manifest and emits warnings for ownership that cannot be set properly, either
# because the current user does not have permissions or because the user/group does not exist.
####################################################################################################################################
sub manifest_ownership_check
{
    my $self = shift;               # Class hash
    my $oManifest = shift;          # Backup manifest

    # Create hashes to track valid/invalid users/groups
    my %oOwnerHash = ();

    # Create hash for each type and owner to be checked
    my $strDefaultUser = getpwuid($<);
    my $strDefaultGroup = getgrgid($();

    my %oFileTypeHash = (&MANIFEST_PATH => true, &MANIFEST_LINK => true, &MANIFEST_FILE => true);
    my %oOwnerTypeHash = (&MANIFEST_SUBKEY_USER => $strDefaultUser, &MANIFEST_SUBKEY_GROUP => $strDefaultGroup);

    # Loop through owner types (user, group)
    foreach my $strOwnerType (sort (keys %oOwnerTypeHash))
    {
        # Loop through all backup paths (base and tablespaces)
        foreach my $strPathKey ($oManifest->keys(MANIFEST_SECTION_BACKUP_PATH))
        {
            # Loop through types (path, link, file)
            foreach my $strFileType (sort (keys %oFileTypeHash))
            {
                my $strSection = "${strPathKey}:${strFileType}";

                # Get users and groups for paths
                if ($oManifest->test($strSection))
                {
                    foreach my $strName ($oManifest->keys($strSection))
                    {
                        my $strOwner = $oManifest->get($strSection, $strName, $strOwnerType);

                        # If root then test to see if the user/group is valid
                        if ($< == 0)
                        {
                            # If the owner has not been tested yet then test it
                            if (!defined($oOwnerHash{$strOwnerType}{$strOwner}))
                            {
                                my $strOwnerId;

                                if ($strOwnerType eq 'user')
                                {
                                    $strOwnerId = getpwnam($strOwner);
                                }
                                else
                                {
                                    $strOwnerId = getgrnam($strOwner);
                                }

                                $oOwnerHash{$strOwnerType}{$strOwner} = defined($strOwnerId) ? true : false;
                            }

                            if (!$oOwnerHash{$strOwnerType}{$strOwner})
                            {
                                $oManifest->set($strSection, $strName, $strOwnerType, $oOwnerTypeHash{$strOwnerType});
                            }
                        }
                        # Else set user/group to current user/group
                        else
                        {
                            if ($strOwner ne $oOwnerTypeHash{$strOwnerType})
                            {
                                $oOwnerHash{$strOwnerType}{$strOwner} = false;
                                $oManifest->set($strSection, $strName, $strOwnerType, $oOwnerTypeHash{$strOwnerType});
                            }
                        }
                   }
                }
            }
        }

        # Output warning for any invalid owners
        if (defined($oOwnerHash{$strOwnerType}))
        {
            foreach my $strOwner (sort (keys $oOwnerHash{$strOwnerType}))
            {
                if (!$oOwnerHash{$strOwnerType}{$strOwner})
                {
                    &log(WARN, "${strOwnerType} ${strOwner} " . ($< == 0 ? "does not exist" : "cannot be set") .
                               ", changed to $oOwnerTypeHash{$strOwnerType}");
                }
            }
        }
    }
}

####################################################################################################################################
# MANIFEST_LOAD
#
# Loads the backup manifest and performs requested tablespace remaps.
####################################################################################################################################
sub manifest_load
{
    my $self = shift;           # Class hash

    if ($self->{oFile}->exists(PATH_BACKUP_CLUSTER, $self->{strBackupPath}))
    {
        # Copy the backup manifest to the db cluster path
        $self->{oFile}->copy(PATH_BACKUP_CLUSTER, $self->{strBackupPath} . '/' . FILE_MANIFEST,
                             PATH_DB_ABSOLUTE, $self->{strDbClusterPath} . '/' . FILE_MANIFEST);

        # Load the manifest into a hash
        my $oManifest = new BackRest::Manifest($self->{oFile}->path_get(PATH_DB_ABSOLUTE,
                                                                        $self->{strDbClusterPath} . '/' . FILE_MANIFEST));

        # Remove the manifest now that it is in memory
        $self->{oFile}->remove(PATH_DB_ABSOLUTE, $self->{strDbClusterPath} . '/' . FILE_MANIFEST);

        # If backup is latest then set it equal to backup label, else verify that requested backup and label match
        my $strBackupLabel = $oManifest->get(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LABEL);

        if ($self->{strBackupPath} eq OPTION_DEFAULT_RESTORE_SET)
        {
            $self->{strBackupPath} = $strBackupLabel;
        }
        elsif ($self->{strBackupPath} ne $strBackupLabel)
        {
            confess &log(ASSERT, "request backup $self->{strBackupPath} and label ${strBackupLabel} do not match " .
                                 ' - this indicates some sort of corruption (at the very least paths have been renamed.');
        }

        if ($self->{strDbClusterPath} ne $oManifest->get(MANIFEST_SECTION_BACKUP_PATH, MANIFEST_KEY_BASE))
        {
            &log(INFO, 'base path remapped to ' . $self->{strDbClusterPath});
            $oManifest->set(MANIFEST_SECTION_BACKUP_PATH, MANIFEST_KEY_BASE, undef, $self->{strDbClusterPath});
        }

        # If tablespaces have been remapped, update the manifest
        if (defined($self->{oRemapRef}))
        {
            foreach my $strPathKey (sort(keys $self->{oRemapRef}))
            {
                my $strRemapPath = ${$self->{oRemapRef}}{$strPathKey};

                # Make sure that the tablespace exists in the manifest
                if (!$oManifest->test(MANIFEST_SECTION_BACKUP_TABLESPACE, $strPathKey))
                {
                    confess &log(ERROR, "cannot remap invalid tablespace ${strPathKey} to ${strRemapPath}");
                }

                # Remap the tablespace in the manifest
                &log(INFO, "remapping tablespace ${strPathKey} to ${strRemapPath}");

                my $strTablespaceLink = $oManifest->get(MANIFEST_SECTION_BACKUP_TABLESPACE, $strPathKey, MANIFEST_SUBKEY_LINK);

                $oManifest->set(MANIFEST_SECTION_BACKUP_PATH, "tablespace:${strPathKey}", undef, $strRemapPath);
                $oManifest->set(MANIFEST_SECTION_BACKUP_TABLESPACE, $strPathKey, MANIFEST_SUBKEY_PATH, $strRemapPath);
                $oManifest->set('base:link', "pg_tblspc/${strTablespaceLink}", MANIFEST_SUBKEY_DESTINATION, $strRemapPath);
            }
        }

        $self->manifest_ownership_check($oManifest);

        return $oManifest;
    }

    confess &log(ERROR, 'backup ' . $self->{strBackupPath} . ' does not exist');
}

####################################################################################################################################
# CLEAN
#
# Checks that the restore paths are empty, or if --force was used then it cleans files/paths/links from the restore directories that
# are not present in the manifest.
####################################################################################################################################
sub clean
{
    my $self = shift;               # Class hash
    my $oManifest = shift;       # Backup manifest

    # Track if files/links/paths where removed
    my %oRemoveHash = (&MANIFEST_FILE => 0, &MANIFEST_PATH => 0, &MANIFEST_LINK => 0);

    # Check each restore directory in the manifest and make sure that it exists and is empty.
    # The --force option can be used to override the empty requirement.
    foreach my $strPathKey ($oManifest->keys(MANIFEST_SECTION_BACKUP_PATH))
    {
        my $strPath = $oManifest->get(MANIFEST_SECTION_BACKUP_PATH, $strPathKey);

        &log(INFO, "checking/cleaning db path ${strPath}");

        if (!$self->{oFile}->exists(PATH_DB_ABSOLUTE,  $strPath))
        {
            confess &log(ERROR, "required db path '${strPath}' does not exist");
        }

        # Load path manifest so it can be compared to deleted files/paths/links that are not in the backup
        my %oPathManifest;
        $self->{oFile}->manifest(PATH_DB_ABSOLUTE, $strPath, \%oPathManifest);

        foreach my $strName (sort {$b cmp $a} (keys $oPathManifest{name}))
        {
            # Skip the root path
            if ($strName eq '.')
            {
                next;
            }

            # If force was not specified then error if any file is found
            if (!$self->{bForce} && !$self->{bDelta})
            {
                confess &log(ERROR, "cannot restore to path '${strPath}' that contains files - " .
                                    'try using --delta if this is what you intended', ERROR_RESTORE_PATH_NOT_EMPTY);
            }

            my $strFile = "${strPath}/${strName}";

            # Determine the file/path/link type
            my $strType = MANIFEST_FILE;

            if ($oPathManifest{name}{$strName}{type} eq 'd')
            {
                $strType = MANIFEST_PATH;
            }
            elsif ($oPathManifest{name}{$strName}{type} eq 'l')
            {
                $strType = MANIFEST_LINK;
            }

            # Build the section name
            my $strSection = "${strPathKey}:${strType}";

            # Check to see if the file/path/link exists in the manifest
            if ($oManifest->test($strSection, $strName))
            {
                my $strUser = $oManifest->get($strSection, $strName, MANIFEST_SUBKEY_USER);
                my $strGroup = $oManifest->get($strSection, $strName, MANIFEST_SUBKEY_GROUP);

                # If ownership does not match, fix it
                if ($strUser ne $oPathManifest{name}{$strName}{user} ||
                    $strGroup ne $oPathManifest{name}{$strName}{group})
                {
                    &log(DEBUG, "setting ${strFile} ownership to ${strUser}:${strGroup}");

                    $self->{oFile}->owner(PATH_DB_ABSOLUTE, $strFile, $strUser, $strGroup);
                }

                # If a link does not have the same destination, then delete it (it will be recreated later)
                if ($strType eq MANIFEST_LINK)
                {
                    if ($strType eq MANIFEST_LINK && $oManifest->get($strSection, $strName, MANIFEST_SUBKEY_DESTINATION) ne
                        $oPathManifest{name}{$strName}{link_destination})
                    {
                        &log(DEBUG, "removing link ${strFile} - destination changed");
                        unlink($strFile) or confess &log(ERROR, "unable to delete file ${strFile}");
                    }
                }
                # Else if file/path mode does not match, fix it
                else
                {
                    my $strMode = $oManifest->get($strSection, $strName, MANIFEST_SUBKEY_MODE);

                    if ($strType ne MANIFEST_LINK && $strMode ne $oPathManifest{name}{$strName}{mode})
                    {
                        &log(DEBUG, "setting ${strFile} mode to ${strMode}");

                        chmod(oct($strMode), $strFile)
                            or confess 'unable to set mode ${strMode} for ${strFile}';
                    }
                }
            }
            # If it does not then remove it
            else
            {
                # If a path then remove it, all the files should have already been deleted since we are going in reverse order
                if ($strType eq MANIFEST_PATH)
                {
                    &log(DEBUG, "removing path ${strFile}");
                    rmdir($strFile) or confess &log(ERROR, "unable to delete path ${strFile}, is it empty?");
                }
                # Else delete a file/link
                else
                {
                    # Delete only if this is not the recovery.conf file.  This is in case the use wants the recovery.conf file
                    # preserved.  It will be written/deleted/preserved as needed in recovery().
                    if (!($strName eq FILE_RECOVERY_CONF && $strType eq MANIFEST_FILE))
                    {
                        &log(DEBUG, "removing file/link ${strFile}");
                        unlink($strFile) or confess &log(ERROR, "unable to delete file/link ${strFile}");
                    }
                }

                $oRemoveHash{$strType} += 1;
            }
        }
    }

    # Loop through types (path, link, file) and emit info if any were removed
    foreach my $strFileType (sort (keys %oRemoveHash))
    {
        if ($oRemoveHash{$strFileType} > 0)
        {
            &log(INFO, "$oRemoveHash{$strFileType} ${strFileType}(s) removed during cleanup");
        }
    }
}

####################################################################################################################################
# BUILD
#
# Creates missing paths and links and corrects ownership/mode on existing paths and links.
####################################################################################################################################
sub build
{
    my $self = shift;            # Class hash
    my $oManifest = shift;       # Backup manifest

    # Build paths/links in each restore path
    foreach my $strSectionPathKey ($oManifest->keys(MANIFEST_SECTION_BACKUP_PATH))
    {
        my $strSectionPath = $oManifest->get(MANIFEST_SECTION_BACKUP_PATH, $strSectionPathKey);

        # Create all paths in the manifest that do not already exist
        my $strSection = "${strSectionPathKey}:path";

        foreach my $strName ($oManifest->keys($strSection))
        {
            # Skip the root path
            if ($strName eq '.')
            {
                next;
            }

            # Create the Path
            my $strPath = "${strSectionPath}/${strName}";

            if (!$self->{oFile}->exists(PATH_DB_ABSOLUTE, $strPath))
            {
                $self->{oFile}->path_create(PATH_DB_ABSOLUTE, $strPath,
                                            $oManifest->get($strSection, $strName, MANIFEST_SUBKEY_MODE));
            }
        }

        # Create all links in the manifest that do not already exist
        $strSection = "${strSectionPathKey}:link";

        if ($oManifest->test($strSection))
        {
            foreach my $strName ($oManifest->keys($strSection))
            {
                my $strLink = "${strSectionPath}/${strName}";

                if (!$self->{oFile}->exists(PATH_DB_ABSOLUTE, $strLink))
                {
                    $self->{oFile}->link_create(PATH_DB_ABSOLUTE,
                                                $oManifest->get($strSection, $strName, MANIFEST_SUBKEY_DESTINATION),
                                                PATH_DB_ABSOLUTE, $strLink);
                }
            }
        }
    }
}

####################################################################################################################################
# RECOVERY
#
# Creates the recovery.conf file.
####################################################################################################################################
sub recovery
{
    my $self = shift;       # Class hash

    # Create recovery.conf path/file
    my $strRecoveryConf = $self->{strDbClusterPath} . '/' . FILE_RECOVERY_CONF;

    # See if recovery.conf already exists
    my $bRecoveryConfExists = $self->{oFile}->exists(PATH_DB_ABSOLUTE, $strRecoveryConf);

    # If RECOVERY_TYPE_PRESERVE then make sure recovery.conf exists and return
    if ($self->{strType} eq RECOVERY_TYPE_PRESERVE)
    {
        if (!$bRecoveryConfExists)
        {
            confess &log(ERROR, "recovery type is $self->{strType} but recovery file does not exist at ${strRecoveryConf}");
        }

        return;
    }

    # In all other cases the old recovery.conf should be removed if it exists
    if ($bRecoveryConfExists)
    {
        $self->{oFile}->remove(PATH_DB_ABSOLUTE, $strRecoveryConf);
    }

    # If RECOVERY_TYPE_NONE then return
    if ($self->{strType} eq RECOVERY_TYPE_NONE)
    {
        return;
    }

    # Write the recovery options from pg_backrest.conf
    my $strRecovery = '';
    my $bRestoreCommandOverride = false;

    if (defined($self->{oRecoveryRef}))
    {
        foreach my $strKey (sort(keys $self->{oRecoveryRef}))
        {
            my $strPgKey = $strKey;
            $strPgKey =~ s/\-/\_/g;

            if ($strPgKey eq 'restore_command')
            {
                $bRestoreCommandOverride = true;
            }

            $strRecovery .= "$strPgKey = '${$self->{oRecoveryRef}}{$strKey}'\n";
        }
    }

    # Write the restore command
    if (!$bRestoreCommandOverride)
    {
        $strRecovery .=  "restore_command = '" . operationWrite(OP_ARCHIVE_GET) . " %f \"%p\"'\n";
    }

    # If RECOVERY_TYPE_DEFAULT do not write target options
    if ($self->{strType} ne RECOVERY_TYPE_DEFAULT)
    {
        # Write the recovery target
        $strRecovery .= "recovery_target_$self->{strType} = '$self->{strTarget}'\n";

        # Write recovery_target_inclusive
        if ($self->{bTargetExclusive})
        {
            $strRecovery .= "recovery_target_inclusive = 'false'\n";
        }
    }

    # Write pause_at_recovery_target
    if ($self->{bTargetResume})
    {
        $strRecovery .= "pause_at_recovery_target = 'false'\n";
    }

    # Write recovery_target_timeline
    if (defined($self->{strTargetTimeline}))
    {
        $strRecovery .= "recovery_target_timeline = '$self->{strTargetTimeline}'\n";
    }

    # Write recovery.conf
    my $hFile;

    open($hFile, '>', $strRecoveryConf)
        or confess &log(ERROR, "unable to open ${strRecoveryConf}: $!");

    syswrite($hFile, $strRecovery)
        or confess "unable to write section ${strRecoveryConf}: $!";

    close($hFile)
        or confess "unable to close ${strRecoveryConf}: $!";
}

####################################################################################################################################
# RESTORE
#
# Takes a backup and restores it back to the original or a remapped location.
####################################################################################################################################
sub restore
{
    my $self = shift;       # Class hash

    # Make sure that Postgres is not running
    if ($self->{oFile}->exists(PATH_DB_ABSOLUTE, $self->{strDbClusterPath} . '/' . FILE_POSTMASTER_PID))
    {
        confess &log(ERROR, 'unable to restore while Postgres is running', ERROR_POSTMASTER_RUNNING);
    }

    # Lock the archive-get process to be sure it is not running
    lockAcquire(OP_ARCHIVE_GET, 900);

    my $oFile = new BackRest::File
    (
        optionGet(OPTION_STANZA),
        optionGet(OPTION_REPO_PATH),
        NONE,
        optionRemote(true)
    );

    # Remove any old archive logs
    if (-e $oFile->path_get(PATH_BACKUP_ARCHIVE_IN))
    {
        remove_tree($oFile->path_get(PATH_BACKUP_ARCHIVE_IN));
            or confess &log(ERROR, "unable to remove " . $oFile->path_get(PATH_BACKUP_ARCHIVE_IN));
    }

    # Log the backup set to restore
    &log(INFO, "Restoring backup set " . $self->{strBackupPath});

    # Make sure the backup path is valid and load the manifest
    my $oManifest = $self->manifest_load();

    # Clean the restore paths
    $self->clean($oManifest);

    # Build paths/links in the restore paths
    $self->build($oManifest);

    # Get variables required for restore
    my $lCopyTimeBegin = $oManifest->epoch(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TIMESTAMP_COPY_START);
    my $bSourceCompression = $oManifest->get(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_COMPRESS) eq 'y' ? true : false;
    my $strCurrentUser = getpwuid($<);
    my $strCurrentGroup = getgrgid($();

    # Create thread queues (or do restore if single-threaded)
    my @oyRestoreQueue;

    if ($self->{iThreadTotal} > 1)
    {
        &log(TRACE, "building thread queues");
    }
    else
    {
        &log(TRACE, "starting restore in main process");
    }

    foreach my $strPathKey ($oManifest->keys(MANIFEST_SECTION_BACKUP_PATH))
    {
        my $strSection = "${strPathKey}:file";

        if ($oManifest->test($strSection))
        {
            if ($self->{iThreadTotal} > 1)
            {
                $oyRestoreQueue[@oyRestoreQueue] = Thread::Queue->new();
            }

            foreach my $strName ($oManifest->keys($strSection))
            {
                if ($self->{iThreadTotal} > 1)
                {
                    $oyRestoreQueue[@oyRestoreQueue - 1]->enqueue("${strPathKey}|${strName}");
                }
                else
                {
                    restoreFile($strPathKey, $strName, $lCopyTimeBegin, $self->{bDelta}, $self->{bForce}, $self->{strBackupPath},
                                $bSourceCompression, $strCurrentUser, $strCurrentGroup, $oManifest, $self->{oFile});
                }
            }
        }
    }

    # If multi-threaded then create threads to copy files
    if ($self->{iThreadTotal} > 1)
    {
        for (my $iThreadIdx = 0; $iThreadIdx < $self->{iThreadTotal}; $iThreadIdx++)
        {
            my %oParam;

            $oParam{copy_time_begin} = $lCopyTimeBegin;
            $oParam{delta} = $self->{bDelta};
            $oParam{force} = $self->{bForce};
            $oParam{backup_path} = $self->{strBackupPath};
            $oParam{source_compression} = $bSourceCompression;
            $oParam{current_user} = $strCurrentUser;
            $oParam{current_group} = $strCurrentGroup;
            $oParam{queue} = \@oyRestoreQueue;
            $oParam{manifest} = $oManifest;

            threadGroupRun($iThreadIdx, 'restore', \%oParam);
        }

        # Complete thread queues
        threadGroupComplete();
    }

    # Create recovery.conf file
    $self->recovery();
}

1;
