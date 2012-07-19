# --
# Kernel/System/PostMaster/Filter/NewTicketOnlyFromKnowEmail.pm - sub part of PostMaster.pm
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PostMaster::Filter::NewTicketOnlyFromKnowEmail;

use strict;
use warnings;

use Kernel::System::Ticket;
use Kernel::System::Email;
use Kernel::System::CustomerUser;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.17 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug} = $Param{Debug} || 0;

    # get needed objects
    for (qw(ConfigObject LogObject DBObject MainObject ParserObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }
    $Self->{CustomerUserObject} = Kernel::System::CustomerUser->new(%Param);
    $Self->{TicketObject} = Kernel::System::Ticket->new(%Param);
    $Self->{EmailObject}  = Kernel::System::Email->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(JobConfig GetParam)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }

    # get config options
    my %Config;
    my %Match;
    my %Set;
    if ( $Param{JobConfig} && ref $Param{JobConfig} eq 'HASH' ) {
        %Config = %{ $Param{JobConfig} };
        if ( $Config{Match} ) {
            %Match = %{ $Config{Match} };
        }
        if ( $Config{Set} ) {
            %Set = %{ $Config{Set} };
        }
    }
    
    # get sender email
    my @EmailAddresses = $Self->{ParserObject}->SplitAddressLine( Line => $Param{GetParam}->{From}, );

    for (@EmailAddresses) {
        $Param{GetParam}->{SenderEmailAddress} = $Self->{ParserObject}->GetEmailAddress( Email => $_, );
    }

    my %List = $Self->{CustomerUserObject}->CustomerSearch(
        PostMasterSearch => lc( $Param{GetParam}->{SenderEmailAddress} ),
    );
    my %CustomerData;
    for ( keys %List ) {
        %CustomerData = $Self->{CustomerUserObject}->CustomerUserDataGet(
            User => $_,
        );
    }

    # if there is no customer id found!
    if ( !$CustomerData{UserLogin} ) {
	# RETURN IF NO CUSTOMER ID
	$Self->{LogObject}->Log( Priority => 'info', Message => "$_ not in database ". $Param{GetParam}->{SenderEmailAddress} );
#    # match 'Match => ???' stuff
#    my $Matched    = '';
#    my $MatchedNot = 0;
#    for ( sort keys %Match ) {
#        if ( $Param{GetParam}->{$_} && $Param{GetParam}->{$_} =~ /$Match{$_}/i ) {
#            $Matched = $1 || '1';
#            if ( $Self->{Debug} > 1 ) {
#                $Self->{LogObject}->Log(
#                    Priority => 'debug',
#                    Message  => "'$Param{GetParam}->{$_}' =~ /$Match{$_}/i matched!",
#                );
#            }
#        }
#        else {
#            $MatchedNot = 1;
#            if ( $Self->{Debug} > 1 ) {
#                $Self->{LogObject}->Log(
#                    Priority => 'debug',
#                    Message  => "'$Param{GetParam}->{$_}' =~ /$Match{$_}/i matched NOT!",
#                );
#            }
#        }
#    }
        # check if new ticket
        my $Tn = $Self->{TicketObject}->GetTNByString( $Param{GetParam}->{Subject} );
        return 1 if $Tn && $Self->{TicketObject}->TicketCheckNumber( Tn => $Tn );

        # set attributes if ticket is created
        for ( keys %Set ) {
            $Param{GetParam}->{$_} = $Set{$_};
            $Self->{LogObject}->Log(
                Priority => 'notice',
                Message =>
                    "Set param '$_' to '$Set{$_}' (Message-ID: $Param{GetParam}->{'Message-ID'}) ",
            );
        }

        # send bounce mail
        my $Subject = $Self->{ConfigObject}->Get(
            'PostMaster::PreFilterModule::NewTicketOnlyFromKnowEmail::Subject'
        );
        my $Body = $Self->{ConfigObject}->Get(
            'PostMaster::PreFilterModule::NewTicketOnlyFromKnowEmail::Body'
        );
        my $Sender = $Self->{ConfigObject}->Get(
            'PostMaster::PreFilterModule::NewTicketOnlyFromKnowEmail::Sender'
        ) || '';
        $Self->{EmailObject}->Send(
            From       => $Sender,
            To         => $Param{GetParam}->{From},
            Subject    => $Subject,
            Body       => $Body,
            Charset    => 'utf-8',
            MimeType   => 'text/plain',
            Loop       => 1,
            Attachment => [
                {
                    Filename    => 'email.txt',
                    Content     => $Param{GetParam}->{Body},
                    ContentType => 'application/octet-stream',
                }
            ],
        );
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message  => "Send reject mail to '$Param{GetParam}->{From}'!",
        );

    }
    return 1;
}

1;
