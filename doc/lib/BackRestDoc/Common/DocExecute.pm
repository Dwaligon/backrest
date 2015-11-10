####################################################################################################################################
# DOC EXECUTE MODULE
####################################################################################################################################
package BackRestDoc::Common::DocExecute;
use parent 'BackRestDoc::Common::DocRender';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);

use lib dirname($0) . '/../lib';
use BackRest::Common::Ini;
use BackRest::Common::Log;
use BackRest::Common::String;
use BackRest::FileCommon;

use lib dirname($0) . '/../test/lib';
use BackRestTest::Common::ExecuteTest;

use BackRestDoc::Common::DocManifest;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_DOC_EXECUTE                                         => 'DocExecute';

use constant OP_DOC_EXECUTE_BACKREST_CONFIG                         => OP_DOC_EXECUTE . '->backrestConfig';
use constant OP_DOC_EXECUTE_EXECUTE                                 => OP_DOC_EXECUTE . '->execute';
use constant OP_DOC_EXECUTE_NEW                                     => OP_DOC_EXECUTE . '->new';
use constant OP_DOC_EXECUTE_POSTGRES_CONFIG                         => OP_DOC_EXECUTE . '->postresConfig';

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
        $strType,
        $oManifest,
        $strRenderOutKey,
        $bExe
    ) =
        logDebugParam
        (
            OP_DOC_EXECUTE_NEW, \@_,
            {name => 'strType'},
            {name => 'oManifest'},
            {name => 'strRenderOutKey'},
            {name => 'bExe'}
        );

    # Create the class hash
    my $self = $class->SUPER::new($strType, $oManifest, $strRenderOutKey);
    bless $self, $class;

    $self->{bExe} = $bExe;

    # Execute cleanup commands
    if ($self->{bExe} && defined($self->{oDoc}->nodeGet('cleanup', false)))
    {
        &log(DEBUG, "do cleanup");

        foreach my $oExecute ($self->{oDoc}->nodeGet('cleanup')->nodeList('execute'))
        {
            $self->execute($oExecute);
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
# execute
####################################################################################################################################
sub execute
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oCommand,
        $iIndent
    ) =
        logDebugParam
        (
            OP_DOC_EXECUTE_EXECUTE, \@_,
            {name => 'oCommand'},
            {name => 'iIndent', default => 1}
        );

    # Working variables
    my $strCommand;
    my $strOutput;

    if ($oCommand->fieldTest('actual-command'))
    {
        $strCommand = $oCommand->fieldGet('actual-command');
        $strOutput = $oCommand->fieldGet('actual-output', false);
    }
    else
    {
        # Command variables
        $strCommand = trim($oCommand->fieldGet('exe-cmd'));
        my $strUser = $oCommand->fieldGet('exe-user', false);
        my $bSuppressError = defined($oCommand->fieldGet('exe-err-suppress', false)) ? $oCommand->fieldGet('exe-err-suppress') : false;
        my $bSuppressStdErr = defined($oCommand->fieldGet('exe-err-suppress-stderr', false)) ?
                                  $oCommand->fieldGet('exe-err-suppress-stderr') : false;
        my $bExeSkip = defined($oCommand->fieldGet('exe-skip', false)) ? $oCommand->fieldGet('exe-skip') : false;
        my $bExeOutput = defined($oCommand->fieldGet('exe-output', false)) ? $oCommand->fieldGet('exe-output') : false;
        my $bExeRetry = defined($oCommand->fieldGet('exe-retry', false)) ? $oCommand->fieldGet('exe-retry') : false;
        my $strExeVar = defined($oCommand->fieldGet('exe-var', false)) ? $oCommand->fieldGet('exe-var') : undef;
        my $iExeExpectedError = defined($oCommand->fieldGet('exe-err-expect', false)) ? $oCommand->fieldGet('exe-err-expect') : undef;

        if ($bExeRetry)
        {
            sleep(1);
        }

        $strUser = defined($strUser) ? $strUser : 'postgres';
        $strCommand = $self->{oManifest}->variableReplace(
            ($strUser eq 'vagrant' ? '' : 'sudo ' . ($strUser eq 'root' ? '' : "-u ${strUser} ")) . $strCommand);

        # Add continuation chars and proper spacing
        $strCommand =~ s/[ ]*\n[ ]*/ \\\n    /smg;

        # Make sure that no lines are greater than 80 chars
        foreach my $strLine (split("\n", $strCommand))
        {
            if (length(trim($strLine)) > 80)
            {
                confess &log(ERROR, "command has a line > 80 characters:\n${strCommand}");
            }
        }

        &log(DEBUG, ('    ' x $iIndent) . "execute: $strCommand");

        if (!$bExeSkip)
        {
            if ($self->{bExe})
            {
                my $oExec = new BackRestTest::Common::ExecuteTest($strCommand,
                                                                  {bSuppressError => $bSuppressError,
                                                                   bSuppressStdErr => $bSuppressStdErr,
                                                                   iExpectedExitStatus => $iExeExpectedError});
                $oExec->begin();
                $oExec->end();

                if ($bExeOutput && defined($oExec->{strOutLog}) && $oExec->{strOutLog} ne '')
                {
                    $strOutput = trim($oExec->{strOutLog});
                    $strOutput =~ s/^[0-9]{4}-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-6][0-9]:[0-6][0-9]\.[0-9]{3} T[0-9]{2}  //smg;
                }

                if (defined($strExeVar))
                {
                    $self->{oManifest}->variableSet($strExeVar, trim($oExec->{strOutLog}));
                }

                if (defined($iExeExpectedError))
                {
                    $strOutput .= trim($oExec->{strErrorLog});
                }
            }
            elsif ($bExeOutput)
            {
                $strOutput = 'Output suppressed for testing';
            }
        }

        if (defined($strExeVar) && !defined($self->{oManifest}->variableGet($strExeVar)))
        {
            $self->{oManifest}->variableSet($strExeVar, '[Unset Variable]');
        }

        $oCommand->fieldSet('actual-command', $strCommand);
        $oCommand->fieldSet('actual-output', $strOutput);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => '$strCommand', value => $strCommand, trace => true},
        {name => '$strOutput', value => $strOutput, trace => true}
    );
}


####################################################################################################################################
# backrestConfig
####################################################################################################################################
sub backrestConfig
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
            OP_DOC_EXECUTE_BACKREST_CONFIG, \@_,
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Working variables
    my $strFile;
    my $strConfig;

    if ($oConfig->fieldTest('actual-file'))
    {
        $strFile = $oConfig->fieldGet('actual-file');
        $strConfig = $oConfig->fieldGet('actual-config');
    }
    else
    {
        # Get filename
        $strFile = $self->{oManifest}->variableReplace($oConfig->paramGet('file'));

        &log(DEBUG, ('    ' x $iDepth) . 'process backrest config: ' . $strFile);

        foreach my $oOption ($oConfig->nodeList('backrest-config-option'))
        {
            my $strSection = $oOption->fieldGet('backrest-config-option-section');
            my $strKey = $oOption->fieldGet('backrest-config-option-key');
            my $strValue = $self->{oManifest}->variableReplace(trim($oOption->fieldGet('backrest-config-option-value'), false));

            if (!defined($strValue))
            {
                delete(${$self->{config}}{$strFile}{$strSection}{$strKey});

                if (keys(${$self->{config}}{$strFile}{$strSection}) == 0)
                {
                    delete(${$self->{config}}{$strFile}{$strSection});
                }

                &log(DEBUG, ('    ' x ($iDepth + 1)) . "reset ${strSection}->${strKey}");
            }
            else
            {
                ${$self->{config}}{$strFile}{$strSection}{$strKey} = $strValue;
                &log(DEBUG, ('    ' x ($iDepth + 1)) . "set ${strSection}->${strKey} = ${strValue}");
            }
        }

        # Save the ini file
        executeTest("sudo chmod 777 $strFile", {bSuppressError => true});
        iniSave($strFile, $self->{config}{$strFile}, true);

        $strConfig = fileStringRead($strFile);

        executeTest("sudo chown postgres:postgres $strFile");
        executeTest("sudo chmod 640 $strFile");

        $oConfig->fieldSet('actual-file', $strFile);
        $oConfig->fieldSet('actual-config', $strConfig);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strFile', value => $strFile, trace => true},
        {name => 'strConfig', value => $strConfig, trace => true}
    );
}

####################################################################################################################################
# postgresConfig
####################################################################################################################################
sub postgresConfig
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
            OP_DOC_EXECUTE_POSTGRES_CONFIG, \@_,
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Working variables
    my $strFile;
    my $strConfig;

    if ($oConfig->fieldTest('actual-file'))
    {
        $strFile = $oConfig->fieldGet('actual-file');
        $strConfig = $oConfig->fieldGet('actual-config');
    }
    else
    {
        # Get filename
        $strFile = $self->{oManifest}->variableReplace($oConfig->paramGet('file'));

        if (!defined(${$self->{'pg-config'}}{$strFile}{base}) && $self->{bExe})
        {
            ${$self->{'pg-config'}}{$strFile}{base} = fileStringRead($strFile);
        }

        my $oConfigHash = $self->{'pg-config'}{$strFile};
        my $oConfigHashNew;

        if (!defined($$oConfigHash{old}))
        {
            $oConfigHashNew = {};
            $$oConfigHash{old} = {}
        }
        else
        {
            $oConfigHashNew = dclone($$oConfigHash{old});
        }

        &log(DEBUG, ('    ' x $iDepth) . 'process postgres config: ' . $strFile);

        foreach my $oOption ($oConfig->nodeList('postgres-config-option'))
        {
            my $strKey = $oOption->paramGet('key');
            my $strValue = $self->{oManifest}->variableReplace(trim($oOption->valueGet()));

            if ($strValue eq '')
            {
                delete($$oConfigHashNew{$strKey});

                &log(DEBUG, ('    ' x ($iDepth + 1)) . "reset ${strKey}");
            }
            else
            {
                $$oConfigHashNew{$strKey} = $strValue;
                &log(DEBUG, ('    ' x ($iDepth + 1)) . "set ${strKey} = ${strValue}");
            }
        }

        # Generate config text
        foreach my $strKey (sort(keys(%$oConfigHashNew)))
        {
            if (defined($strConfig))
            {
                $strConfig .= "\n";
            }

            $strConfig .= "${strKey} = $$oConfigHashNew{$strKey}";
        }

        # Save the conf file
        if ($self->{bExe})
        {
            executeTest("sudo chown vagrant $strFile");

            fileStringWrite($strFile, $$oConfigHash{base} .
                            (defined($strConfig) ? "\n# pgBackRest Configuration\n${strConfig}" : ''));

            executeTest("sudo chown postgres $strFile");
        }

        $$oConfigHash{old} = $oConfigHashNew;

        $oConfig->fieldSet('actual-file', $strFile);
        $oConfig->fieldSet('actual-config', $strConfig);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strFile', value => $strFile, trace => true},
        {name => 'strConfig', value => $strConfig, trace => true}
    );
}

1;
