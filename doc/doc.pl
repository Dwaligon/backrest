#!/usr/bin/perl
####################################################################################################################################
# pg_backrest.pl - Simple Postgres Backup and Restore
####################################################################################################################################

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

$SIG{__DIE__} = sub { Carp::confess @_ };

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);
use Storable;
use XML::Checker::Parser;
# use XML::Simple;

use lib dirname($0) . '/lib';
use BackRestDoc::Common::Doc;
use BackRestDoc::Common::DocConfig;
use BackRestDoc::Html::DocHtmlSite;
use BackRestDoc::Latex::DocLatex;
use BackRestDoc::Common::DocRender;

use lib dirname($0) . '/../lib';
use BackRest::Common::Log;
use BackRest::Common::String;
use BackRest::Config::Config;
use BackRest::FileCommon;

####################################################################################################################################
# Usage
####################################################################################################################################

=head1 NAME

doc.pl - Generate pgBackRest documentation

=head1 SYNOPSIS

doc.pl [options] [operation]

 General Options:
   --help           display usage and exit

=cut

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_MAIN                                                => 'Main';

use constant OP_MAIN_DOC_PROCESS                                    => OP_MAIN . '::docProcess';

####################################################################################################################################
# Load command line parameters and config
####################################################################################################################################
my $bHelp = false;                                  # Display usage
my $bVersion = false;                               # Display version
my $bQuiet = false;                                 # Sets log level to ERROR
my $strLogLevel = 'info';                           # Log level for tests
my $strProjectName = 'pgBackRest';                  # Project name to use in docs
my $strPdfProjectName = $strProjectName;            # Project name to use in PDF docs
my $strExeName = 'pg_backrest';                     # Exe name to use in docs
my $bHtml = false;                                  # Generate full html documentation
my $strHtmlRoot = '/';                              # Root html page
my $bNoExe = false;                                 # Should commands be executed when buildng help? (for testing only)
my $bPDF = false;                                   # Generate the PDF file
my $bUseCached = false;                             # Use cached data to generate the docs (for testing code changes only)

GetOptions ('help' => \$bHelp,
            'version' => \$bVersion,
            'quiet' => \$bQuiet,
            'log-level=s' => \$strLogLevel,
            'html' => \$bHtml,
            'html-root=s' => \$strHtmlRoot,
            'pdf' => \$bPDF,
            'no-exe', \$bNoExe,
            'use-cached', \$bUseCached,
            'project-name=s', \$strProjectName,
            'pdf-project-name=s', \$strPdfProjectName)
    or pod2usage(2);

# Display version and exit if requested
if ($bHelp || $bVersion)
{
    print 'pg_backrest ' . version_get() . " doc builder\n";

    if ($bHelp)
    {
        print "\n";
        pod2usage();
    }

    exit 0;
}

# Set no-exe if use-cached
if ($bUseCached)
{
    $bNoExe = true;
}

# Set console log level
if ($bQuiet)
{
    $strLogLevel = 'off';
}

logLevelSet(undef, uc($strLogLevel));

# Get the base path
my $strBasePath = abs_path(dirname($0));
my $strOutputPath = "${strBasePath}/output";

sub docProcess
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strXmlIn,
        $strMdOut,
        $oHtmlSite
    ) =
        logDebugParam
        (
            OP_MAIN_DOC_PROCESS, \@_,
            {name => 'strXmlIn'},
            {name => 'strMdOut'},
            {name => 'oHtmlSite'}
        );

    # Build the document from xml
    my $oDoc = new BackRestDoc::Common::Doc($strXmlIn);

    # Write markdown
    my $oRender = new BackRestDoc::Common::DocRender('markdown', $strProjectName, $strExeName);
    $oRender->save($strMdOut, $oHtmlSite->variableReplace($oRender->process($oDoc)));
}

my $oRender = new BackRestDoc::Common::DocRender('text', $strProjectName, $strExeName);
my $oDocConfig = new BackRestDoc::Common::DocConfig(new BackRestDoc::Common::Doc("${strBasePath}/xml/reference.xml"), $oRender);
$oDocConfig->helpDataWrite();

# Only generate the HTML/PDF when requested
if ($bHtml || $bPDF)
{
    my $strUserGuideFile = "${strOutputPath}/user-guide.xml";
    my $strVarFile = "${strOutputPath}/var.xml";
    my $oUserGuide;
    my $oVar;

    if ($bUseCached && -e $strUserGuideFile && -e $strVarFile)
    {
        $oUserGuide = retrieve($strUserGuideFile);
        $oVar = retrieve($strVarFile);
        #
        # use Data::Dumper; confess Dumper($oSite);
    }

    # Create the out path if it does not exist
    if (!-e $strOutputPath)
    {
        mkdir($strOutputPath)
            or confess &log(ERROR, "unable to create path ${strOutputPath}");
    }

    # !!! Create Html Site Object to perform variable replacements on markdown and test
    # !!! This should be replaced with a more generic site object in the future
    my $oHtmlSite =
        new BackRestDoc::Html::DocHtmlSite
        (
            $oVar,
            $oUserGuide,
            new BackRestDoc::Common::DocRender('html', $strProjectName, $strExeName),
            $oDocConfig,
            "${strBasePath}/xml",
            "${strOutputPath}/html",
            "${strBasePath}/resource/html/default.css",
            $strHtmlRoot,
            !$bNoExe
        );

    docProcess("${strBasePath}/xml/index.xml", "${strBasePath}/../README.md", $oHtmlSite);
    docProcess("${strBasePath}/xml/change-log.xml", "${strBasePath}/../CHANGELOG.md", $oHtmlSite);

    # Generate HTML
    $oHtmlSite->process();

    if (!$bUseCached)
    {
        store($oHtmlSite->{oSite}->{page}->{'user-guide'}->{oDoc}->{oDoc}, $strUserGuideFile);
        store($oHtmlSite->{var}, $strVarFile);
    }

    # Only generate the PDF file when requested
    $oHtmlSite->{var}->{backrest} = $strPdfProjectName;

    my $oLatex =
        new BackRestDoc::Latex::DocLatex
        (
            $oHtmlSite->{var},
            $oHtmlSite->{oSite},
            new BackRestDoc::Common::DocRender('latex', $strPdfProjectName, $strExeName),
            $oDocConfig,
            "${strBasePath}/xml",
            "${strOutputPath}/latex",
            "${strBasePath}/resource/latex/preamble.tex",
            !$bNoExe
        );

    if ($bPDF)
    {
        $oLatex->process();
    }
}
