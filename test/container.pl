#!/usr/bin/perl
####################################################################################################################################
# container.pl - Build docker containers for testing and documentation
####################################################################################################################################

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess longmess);

# Convert die to confess to capture the stack trace
$SIG{__DIE__} = sub { Carp::confess @_ };

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Getopt::Long qw(GetOptions);
use Scalar::Util qw(blessed);
# use Cwd qw(abs_path);
# use Pod::Usage qw(pod2usage);
# use Scalar::Util qw(blessed);

use lib dirname($0) . '/../lib';
use BackRest::Common::Ini;
# use BackRest::Common::Ini;
use BackRest::Common::Log;
use BackRest::FileCommon;
# use BackRest::Db;

use lib dirname($0) . '/lib';
use BackRestTest::Common::ExecuteTest;
# use BackRestTest::CommonTest;
# use BackRestTest::CompareTest;
# use BackRestTest::ConfigTest;
# use BackRestTest::FileTest;
# use BackRestTest::HelpTest;

####################################################################################################################################
# Usage
####################################################################################################################################

=head1 NAME

container.pl - Docker Container Build

=head1 SYNOPSIS

container.pl [options]

 Build Options:
   --os                 os to build (defaults to all)

 Configuration Options:
   --log-level          log level to use for tests (defaults to info)
   --quiet, -q          equivalent to --log-level=off

 General Options:
   --version            display version and exit
   --help               display usage and exit
=cut

####################################################################################################################################
# Command line parameters
####################################################################################################################################
my $strLogLevel = 'info';
my $bVersion = false;
my $bHelp = false;
my $bQuiet = false;

GetOptions ('q|quiet' => \$bQuiet,
            'version' => \$bVersion,
            'help' => \$bHelp,
            'log-level=s' => \$strLogLevel)
    or pod2usage(2);

# Display version and exit if requested
if ($bVersion || $bHelp)
{
    syswrite(*STDOUT, 'pgBackRest ' . BACKREST_VERSION . " Docker Container Build\n");

    if ($bHelp)
    {
        syswrite(*STDOUT, "\n");
        pod2usage();
    }

    exit 0;
}

if (@ARGV > 0)
{
    syswrite(*STDOUT, "invalid parameter\n\n");
    pod2usage();
}

####################################################################################################################################
# Setup
####################################################################################################################################
# Set a neutral umask so tests work as expected
umask(0);

# Set console log level
if ($bQuiet)
{
    $strLogLevel = 'off';
}

logLevelSet(undef, uc($strLogLevel));

# Create temp path
my $strTempPath = dirname(abs_path($0)) . '/.vagrant/docker';

if (!-e $strTempPath)
{
    mkdir $strTempPath
        or confess &log(ERROR, "unable to create ${strTempPath}");
}

####################################################################################################################################
# Valid OS list
####################################################################################################################################
use constant OS_CO6                                                 => 'co6';
use constant OS_CO7                                                 => 'co7';
use constant OS_U12                                                 => 'u12';
use constant OS_U14                                                 => 'u14';

my @stryOS =
(
    OS_CO6,                                 # CentOS 6
    OS_CO7,                                 # CentOS 7
    OS_U12,                                 # Ubuntu 12.04
    OS_U14                                  # Ubuntu 14.04
);

use constant TEST_GROUP                                             => 'admin';
use constant TEST_GROUP_ID                                          => 1000;
use constant TEST_USER                                              => 'vagrant';
use constant TEST_USER_ID                                           => TEST_GROUP_ID;

use constant POSTGRES_GROUP                                         => 'postgres';
use constant POSTGRES_GROUP_ID                                      => 5000;
use constant POSTGRES_USER                                          => POSTGRES_GROUP;
use constant POSTGRES_USER_ID                                       => POSTGRES_GROUP_ID;

use constant BACKREST_GROUP                                         => POSTGRES_GROUP;
use constant BACKREST_GROUP_ID                                      => POSTGRES_GROUP_ID;
use constant BACKREST_USER                                          => 'backrest';
use constant BACKREST_USER_ID                                       => 5001;

####################################################################################################################################
# User/group creation
####################################################################################################################################
sub groupCreate
{
    my $strOS = shift;
    my $strName = shift;
    my $iId = shift;

    return "RUN groupadd -g${iId} ${strName}";
}

sub userCreate
{
    my $strOS = shift;
    my $strName = shift;
    my $iId = shift;
    my $strGroup = shift;

    if ($strOS eq OS_CO6 || $strOS eq OS_CO7)
    {
        return "RUN adduser -g${strGroup} -u${iId} -n ${strName}";
    }
    elsif ($strOS eq OS_U12 || $strOS eq OS_U14)
    {
        return "RUN adduser --uid=${iId} --ingroup=${strGroup} --disabled-password --gecos \"\" ${strName}";
    }

    confess &log(ERROR, "unable to create user for os '${strOS}'");
}

sub postgresGroupCreate
{
    my $strOS = shift;

    return "# Create PostgreSQL group\n" .
           groupCreate($strOS, POSTGRES_GROUP, POSTGRES_GROUP_ID);
}

sub postgresUserCreate
{
    my $strOS = shift;

    return "# Create PostgreSQL user\n" .
           userCreate($strOS, POSTGRES_USER, POSTGRES_USER_ID, POSTGRES_GROUP);
}

sub backrestUserCreate
{
    my $strOS = shift;

    return "# Create BackRest group\n" .
           userCreate($strOS, BACKREST_USER, BACKREST_USER_ID, BACKREST_GROUP);
}

####################################################################################################################################
# Create pg_backrest.conf
####################################################################################################################################
sub backrestConfigCreate
{
    my $strOS = shift;
    my $strUser = shift;
    my $strGroup = shift;

    return "# Create pg_backrest.conf\n" .
           "RUN touch /etc/pg_backrest.conf\n" .
           "RUN chmod 640 /etc/pg_backrest.conf\n" .
           "RUN chown ${strUser}:${strGroup} /etc/pg_backrest.conf";
}

####################################################################################################################################
# Setup SSH
####################################################################################################################################
sub sshSetup
{
    my $strOS = shift;
    my $strUser = shift;
    my $strGroup = shift;

    return "# Setup SSH\n" .
           "RUN mkdir /home/${strUser}/.ssh\n" .
           "COPY id_rsa  /home/${strUser}/.ssh/id_rsa\n" .
           "COPY id_rsa.pub  /home/${strUser}/.ssh/authorized_keys\n" .
           "RUN chown -R ${strUser}:${strGroup} /home/${strUser}/.ssh\n" .
           "RUN chmod 700 /home/${strUser}/.ssh\n" .
           "RUN echo 'Host *' > /home/${strUser}/.ssh/config\n" .
           "RUN echo '    StrictHostKeyChecking no' >> /home/${strUser}/.ssh/config\n" .
           "RUN echo '    LogLevel quiet' >> /home/${strUser}/.ssh/config";
}

####################################################################################################################################
# Repo Setup
####################################################################################################################################
sub repoSetup
{
    my $strOS = shift;
    my $strUser = shift;
    my $strGroup = shift;

    return "# Setup repository\n" .
           "RUN mkdir /var/lib/backrest\n" .
           "RUN chown -R ${strUser}:${strGroup} /var/lib/backrest\n" .
           "RUN chmod 750 /var/lib/backrest";
}

####################################################################################################################################
# Install Perl packages
####################################################################################################################################
sub perlInstall
{
    my $strOS = shift;

    my $strImage =
        "# Install Perl packages\n";

    if ($strOS eq OS_CO6)
    {
        $strImage .=
            "RUN yum -y install perl perl-Time-HiRes perl-parent perl-JSON perl-Digest-SHA perl-DBD-Pg";
    }
    elsif ($strOS eq OS_CO7)
    {
        $strImage .=
            "RUN yum -y install perl perl-Thread-Queue perl-JSON-PP perl-Digest-SHA perl-DBD-Pg";
    }
    elsif ($strOS eq OS_U12 || $strOS eq OS_U14)
    {
        $strImage .=
            "RUN apt-get -y install libdbd-pg-perl libdbi-perl libnet-daemon-perl libplrpc-perl";
    }

    return $strImage;
}

####################################################################################################################################
# Build containers
####################################################################################################################################
eval
{
    # Create SSH key (if it does not already exist)
    if (-e "${strTempPath}/id_rsa")
    {
        &log(INFO, "SSH key already exists");
    }
    else
    {
        &log(INFO, "Building SSH keys...");

        executeTest("ssh-keygen -f ${strTempPath}/id_rsa -t rsa -b 768 -N ''", {bSuppressStdErr => true});
    }

    foreach my $strOS (@stryOS)
    {
        my $strImage;
        my $strImageName;

        # Base image
        ###########################################################################################################################
        $strImageName = "${strOS}-base";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Base Container\nFROM ";

        if ($strOS eq OS_CO6)
        {
            $strImage .= 'centos:6';
        }
        elsif ($strOS eq OS_CO7)
        {
            $strImage .= 'centos:7';
        }
        elsif ($strOS eq OS_U12)
        {
            $strImage .= 'ubuntu:12.04';
        }
        elsif ($strOS eq OS_U14)
        {
            $strImage .= 'ubuntu:14.04';
        }

        # Install SSH
        $strImage .= "\n\n# Install SSH\n";

        if ($strOS eq OS_CO6 || $strOS eq OS_CO7)
        {
            $strImage .= "RUN yum -y install openssh-server openssh-clients\n";
        }
        elsif ($strOS eq OS_U12 || $strOS eq OS_U14)
        {
            $strImage .= "RUN apt-get -y install openssh-server\n";
        }

        $strImage .=
            "RUN rm -f /etc/ssh/ssh_host_rsa_key*\n" .
            "RUN ssh-keygen -t rsa -b 768 -f /etc/ssh/ssh_host_rsa_key";

        # Create PostgreSQL Group
        $strImage .= "\n\n" . postgresGroupCreate($strOS);

        # Add PostgreSQL packages
        $strImage .= "\n\n# Add PostgreSQL packages\n";

        if ($strOS eq OS_CO6)
        {
            $strImage .=
                "RUN rpm -ivh http://yum.postgresql.org/9.0/redhat/rhel-6-x86_64/pgdg-centos90-9.0-5.noarch.rpm\n" .
                "RUN rpm -ivh http://yum.postgresql.org/9.1/redhat/rhel-6-x86_64/pgdg-centos91-9.1-4.noarch.rpm\n" .
                "RUN rpm -ivh http://yum.postgresql.org/9.2/redhat/rhel-6-x86_64/pgdg-centos92-9.2-6.noarch.rpm\n" .
                "RUN rpm -ivh http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-centos93-9.3-1.noarch.rpm\n" .
                "RUN rpm -ivh http://yum.postgresql.org/9.4/redhat/rhel-6-x86_64/pgdg-centos94-9.4-1.noarch.rpm";
        }
        elsif ($strOS eq OS_CO7)
        {
            $strImage .=
                "RUN rpm -ivh http://yum.postgresql.org/9.3/redhat/rhel-7-x86_64/pgdg-centos93-9.3-1.noarch.rpm\n" .
                "RUN rpm -ivh http://yum.postgresql.org/9.4/redhat/rhel-7-x86_64/pgdg-centos94-9.4-1.noarch.rpm\n" .
                "RUN rpm -ivh http://yum.postgresql.org/9.5/redhat/rhel-7-x86_64/pgdg-centos95-9.5-1.noarch.rpm";
        }
        elsif ($strOS eq OS_U12 || $strOS eq OS_U14)
        {
            if ($strOS eq OS_U12)
            {
                $strImage .=
                    "RUN apt-get install -y sudo\n";
            }

            $strImage .=
                "RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ " .
                    ($strOS eq OS_U12 ? 'precise' : 'trusty') .
                    "-pgdg main 9.5' >> /etc/apt/sources.list.d/pgdg.list\n" .
                "RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -\n" .
                "RUN apt-get update";
        }

        # Create test group
        $strImage .=
            "\n\n# Create test group\n" .
            groupCreate($strOS, TEST_GROUP, TEST_GROUP_ID) . "\n";

        if ($strOS eq OS_CO6 || $strOS eq OS_CO7)
        {
            $strImage .=
                "RUN yum -y install sudo\n" .
                "RUN echo '%" . TEST_GROUP . "        ALL=(ALL)       NOPASSWD: ALL' > /etc/sudoers.d/" . TEST_GROUP . "\n" .
                "RUN sed -i 's/^Defaults    requiretty\$/\\# Defaults    requiretty/' /etc/sudoers";
        }
        elsif ($strOS eq OS_U12 || $strOS eq OS_U14)
        {
            $strImage .=
                "RUN sed -i 's/^\\\%admin.*\$/\\\%" . TEST_GROUP . " ALL\\=\\(ALL\\) NOPASSWD\\: ALL/' /etc/sudoers";
        }

        # Create test user
        $strImage .=
            "\n\n# Create test user\n" .
            userCreate($strOS, TEST_USER, TEST_USER_ID, TEST_GROUP);

        # Suppress dpkg interactive output
        if ($strOS eq OS_U12 || $strOS eq OS_U14)
        {
            $strImage .=
                "\n\n# Suppress dpkg interactive output\n" .
                "RUN rm /etc/apt/apt.conf.d/70debconf";
        }

        # Start SSH when container starts
        $strImage .=
            "\n\n# Start SSH when container starts\n";

        if ($strOS eq OS_CO6)
        {
            $strImage .=
                "ENTRYPOINT service sshd restart && bash";
        }
        elsif ($strOS eq OS_CO7)
        {
            $strImage .=
                # "ENTRYPOINT systemctl start sshd.service && bash";
                "ENTRYPOINT /usr/sbin/sshd -D && bash";
        }
        elsif ($strOS eq OS_U12)
        {
            $strImage .=
                "ENTRYPOINT /etc/init.d/ssh start && bash";
        }
        elsif ($strOS eq OS_U14)
        {
            $strImage .=
                "ENTRYPOINT service ssh restart && bash";
        }

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "$strImage\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}",
                    {bSuppressStdErr => true});

        # Db image
        ###########################################################################################################################
        $strImageName = "${strOS}-db";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Database Container\nFROM backrest/${strOS}-base";

        # Create PostgreSQL User
        $strImage .= "\n\n" . postgresUserCreate($strOS);

        # Install SSH key
        $strImage .=
            "\n\n" . sshSetup($strOS, POSTGRES_USER, POSTGRES_GROUP);

        # Install PostgreSQL
        $strImage .=
            "\n\n# Install PostgreSQL\n";

        if ($strOS eq OS_CO6)
        {
            $strImage .=
                "RUN yum -y install postgresql90-server\n" .
                "RUN yum -y install postgresql91-server\n" .
                "RUN yum -y install postgresql92-server\n" .
                "RUN yum -y install postgresql93-server\n" .
                "RUN yum -y install postgresql94-server";
        }
        elsif ($strOS eq OS_CO7)
        {
            $strImage .=
                "RUN yum -y install postgresql93-server\n" .
                "RUN yum -y install postgresql94-server\n" .
                "RUN yum -y install postgresql95-server";
        }
        elsif ($strOS eq OS_U12)
        {
            $strImage .=
                "RUN apt-get install -y postgresql-9.4\n" .
                "RUN pg_dropcluster --stop 9.4 main\n" .
                "RUN apt-get install -y postgresql-9.3\n" .
                "RUN pg_dropcluster --stop 9.3 main\n" .
                "RUN apt-get install -y postgresql-9.2\n" .
                "RUN pg_dropcluster --stop 9.2 main\n" .
                "RUN apt-get install -y postgresql-9.1\n" .
                "RUN pg_dropcluster --stop 9.1 main\n" .
                "RUN apt-get install -y postgresql-9.0\n" .
                "RUN pg_dropcluster --stop 9.0 main\n" .
                "RUN apt-get install -y postgresql-8.4\n" .
                "RUN pg_dropcluster --stop 8.4 main";
        }
        elsif ($strOS eq OS_U14)
        {
            $strImage .=
                "RUN apt-get install -y postgresql-9.5\n" .
                "RUN pg_dropcluster --stop 9.5 main\n" .
                "RUN apt-get install -y postgresql-9.4\n" .
                "RUN pg_dropcluster --stop 9.4 main\n" .
                "RUN apt-get install -y postgresql-9.3\n" .
                "RUN pg_dropcluster --stop 9.3 main\n" .
                "RUN apt-get install -y postgresql-9.2\n" .
                "RUN pg_dropcluster --stop 9.2 main\n" .
                "RUN apt-get install -y postgresql-9.1\n" .
                "RUN pg_dropcluster --stop 9.1 main\n" .
                "RUN apt-get install -y postgresql-9.0\n" .
                "RUN pg_dropcluster --stop 9.0 main";
        }

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}",
                    {bSuppressStdErr => true});


        # Db Doc image
        ###########################################################################################################################
        $strImageName = "${strOS}-db-doc";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Database Doc Container\nFROM backrest/${strOS}-db";

        # Create pg_backrest.conf
        $strImage .=
            "\n\n" . backrestConfigCreate($strOS, POSTGRES_USER, POSTGRES_GROUP);

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}",
                    {bSuppressStdErr => true});


        # Backup image
        ###########################################################################################################################
        $strImageName = "${strOS}-backup";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Backup Container\nFROM backrest/${strOS}-base";

        # Create BackRest User
        $strImage .= "\n\n" . backrestUserCreate($strOS);

        # Install SSH key
        $strImage .=
            "\n\n" . sshSetup($strOS, BACKREST_USER, BACKREST_GROUP);

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}",
                    {bSuppressStdErr => true});


        # Backup Doc image
        ###########################################################################################################################
        $strImageName = "${strOS}-backup-doc";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Backup Doc Container\nFROM backrest/${strOS}-backup";

        # Create pg_backrest.conf
        $strImage .=
            "\n\n" . backrestConfigCreate($strOS, BACKREST_USER, BACKREST_GROUP);

        # Setup repository
        $strImage .=
            "\n\n" . repoSetup($strOS, BACKREST_USER, BACKREST_GROUP);

        # Install Perl packages
        $strImage .=
            "\n\n" . perlInstall($strOS) . "\n";

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}",
                    {bSuppressStdErr => true});


        # Test image
        ###########################################################################################################################
        $strImageName = "${strOS}-test";
        &log(INFO, "Building ${strImageName} image...");

        $strImage = "# Test Container\nFROM backrest/${strOS}-db";

        # Create BackRest User
        $strImage .= "\n\n" . backrestUserCreate($strOS);

        # Install SSH key
        $strImage .=
            "\n\n" . sshSetup($strOS, BACKREST_USER, BACKREST_GROUP);

        # Install SSH key for vagrant user
        $strImage .=
            "\n\n" . sshSetup($strOS, TEST_USER, TEST_GROUP);

        # Put vagrant user in postgres group so tests work properly (this will be removed in the future)
        $strImage .=
            "\n\n# Add postgres group to vagrant user\n" .
            "RUN usermod -g " . BACKREST_GROUP . " -G " . TEST_GROUP . " " . TEST_USER;

        # Install Perl packages
        $strImage .=
            "\n\n" . perlInstall($strOS) . "\n";

        # Make PostgreSQL home group readable
        $strImage .=
            "\n\n# Make vagrant home dir readable\n" .
            "RUN chown -R vagrant:postgres /home/vagrant\n" .
            "RUN chmod g+r,g+x /home/vagrant";

        # Write the image
        fileStringWrite("${strTempPath}/${strImageName}", "${strImage}\n", false);
        executeTest("docker build -f ${strTempPath}/${strImageName} -t backrest/${strImageName} ${strTempPath}",
                    {bSuppressStdErr => true});

    }
};

if ($@)
{
    my $oMessage = $@;

    # If a backrest exception then return the code - don't confess
    if (blessed($oMessage) && $oMessage->isa('BackRest::Common::Exception'))
    {
        syswrite(*STDOUT, $oMessage->trace());
        exit $oMessage->code();
    }

    syswrite(*STDOUT, $oMessage);
    exit 255;;
}
