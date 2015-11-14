####################################################################################################################################
# HostTest.pm - Encapsulate a docker host for testing
####################################################################################################################################
package BackRestTest::Common::HostTest;

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Cwd qw(abs_path);
use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);

use lib dirname($0) . '/../lib';
use BackRest::Common::Log;

use BackRestTest::Common::ExecuteTest;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_HOST_TEST                                           => 'LogTest';

use constant OP_HOST_TEST_EXECUTE                                   => OP_HOST_TEST . "->execute";
use constant OP_HOST_TEST_NEW                                       => OP_HOST_TEST . "->new";

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;          # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{strName},
        $self->{strOS},
        $self->{strImage}
    ) =
        logDebugParam
        (
            OP_HOST_TEST_NEW, \@_,
            {name => 'strName', trace => true},
            {name => 'strOS', trace => true},
            {name => 'strImage', trace => true}
        );

    $self->{strActualImage} = "vagrant/$self->{strOS}-$self->{strImage}";

    executeTest("docker kill $self->{strName}", {bSuppressError => true});
    executeTest("docker rm $self->{strName}", {bSuppressError => true});
    executeTest("docker run -itd --name=$self->{strName} -v /backrest:/backrest $self->{strActualImage}");

    $self->{bActive} = true;

        # <execute>
        #     <exe-cmd>docker kill db-master</exe-cmd>
        #     <exe-user>docker</exe-user>
        #     <exe-err-suppress/>
        # </execute>
        # <execute>
        #     <exe-cmd>docker rm db-master</exe-cmd>
        #     <exe-user>docker</exe-user>
        #     <exe-err-suppress/>
        # </execute>
        # <execute>
        #     <exe-cmd>docker run -itd --name=db-master -v /backrest:/backrest vagrant/u14-db</exe-cmd>
        #     <exe-user>docker</exe-user>
        # </execute>

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self, trace => true}
    );
}

####################################################################################################################################
# logAdd
####################################################################################################################################
sub execute
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strUser,
        $strCommand
    ) =
        logDebugParam
        (
            OP_HOST_TEST_EXECUTE, \@_,
            {name => 'strUser'},
            {name => 'strCommand'}
        );

    # Return from function and log return values if any
    logDebugReturn($strOperation);
}

1;
