#import <Foundation/NSDistributedNotificationCenter.h>
#import <IMDaemonCore/IMDMessageStore.h>
#import <IMDaemonCore/IMDServiceSession.h>
#import <IMFoundation/FZMessage.h>
#import <version.h>

// TODO: this is very incorrect (are the flags XOR’d?), however it seems to
// always be this value
#define IMMessageItemFlagsTypingBegan (IMMessageItemFlags)4096

#pragma mark - Communication with SpringBoard

void HBTSPostMessage(HBTSMessageType type, NSString *name, BOOL isTyping) {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSDictionary <NSString *, id> *data = @{
			kHBTSMessageTypeKey: @(type),
			kHBTSMessageSenderKey: name ?: @"",
			kHBTSMessageIsTypingKey: @(isTyping)
		};

		LMConnectionSendOneWayData(&springboardService, 0, (__bridge CFDataRef)LMDataForPropertyList(data));
	});
}

#pragma mark - Typing/read notifications

@interface IMDServiceSession ()

- (void)_typeStatus_didReceiveMessage:(FZMessage *)message;

@end

%hook IMDServiceSession

%new - (void)_typeStatus_didReceiveMessage:(FZMessage *)message {
	if (message.isTypingMessage && message.flags == IMMessageItemFlagsTypingBegan) {
		HBTSPostMessage(HBTSMessageTypeTyping, message.handle, YES);
	} else {
		HBTSPostMessage(HBTSMessageTypeTypingEnded, message.handle, NO);
	}
}

%group EddyCue
- (void)didReceiveMessage:(FZMessage *)message forChat:(id)chat style:(unsigned char)style account:(id)account {
	%orig;
	[self _typeStatus_didReceiveMessage:message];
}
%end

%group CraigFederighi
- (void)didReceiveMessage:(FZMessage *)message forChat:(id)chat style:(unsigned char)style {
	%orig;
	[self _typeStatus_didReceiveMessage:message];
}
%end

- (void)didReceiveMessageReadReceiptForMessageID:(NSString *)messageID date:(NSDate *)date completionBlock:(id)completion {
	%orig;
	HBTSPostMessage(HBTSMessageTypeReadReceipt, [[%c(IMDMessageStore) sharedInstance] messageWithGUID:messageID].handle, NO);
}

%end

#pragma mark - Test functions

void HBTSTestTyping() {
	HBTSPostMessage(HBTSMessageTypeTyping, @"example@hbang.ws", NO);
}

void HBTSTestRead() {
	HBTSPostMessage(HBTSMessageTypeReadReceipt, @"example@hbang.ws", NO);
}

#pragma mark - Constructor

%ctor {
	%init;

	if (IS_IOS_OR_NEWER(iOS_9_0)) {
		%init(EddyCue);
	} else {
		%init(CraigFederighi);
	}

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)HBTSTestTyping, CFSTR("ws.hbang.typestatus/TestTyping"), NULL, kNilOptions);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)HBTSTestRead, CFSTR("ws.hbang.typestatus/TestRead"), NULL, kNilOptions);
}
