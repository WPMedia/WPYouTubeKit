//
//  Copyright (c) 2013-2016 Cédric Luthi. All rights reserved.
//

#import "XCDYouTubeVideoOperation.h"

#import <objc/runtime.h>

#import "XCDYouTubeVideo+Private.h"
#import "XCDYouTubeError.h"
#import "XCDYouTubeVideoWebpage.h"
#import "XCDYouTubeDashManifestXML.h"
#import "XCDYouTubeLogger+Private.h"

typedef NS_ENUM(NSUInteger, XCDYouTubeRequestType) {
	// Removed other enums but keeps raw values for remaining ones
	XCDYouTubeRequestTypeWatchPage = 2,
	XCDYouTubeRequestTypeDashManifest = 5,
};

@interface XCDYouTubeVideoOperation ()
@property (atomic, copy, readonly) NSString *videoIdentifier;
@property (atomic, copy, readonly) NSString *languageIdentifier;
@property (atomic, strong, readonly) NSArray <NSHTTPCookie *> *cookies;
@property (atomic, strong, readonly) NSArray <NSString *> *customPatterns;
@property (atomic, assign) NSInteger requestCount;
@property (atomic, assign) XCDYouTubeRequestType requestType;
@property (atomic, strong) NSMutableArray *eventLabels;
@property (atomic, strong) XCDYouTubeVideo *lastSuccessfulVideo;
@property (atomic, readonly) NSURLSession *session;
@property (atomic, strong) NSURLSessionDataTask *dataTask;

@property (atomic, assign) BOOL isExecuting;
@property (atomic, assign) BOOL isFinished;
@property (atomic, readonly) dispatch_semaphore_t operationStartSemaphore;

@property (atomic, strong) XCDYouTubeVideoWebpage *webpage;
@property (atomic, strong) NSError *lastError;
@property (atomic, strong) NSError *youTubeError; // Error from YouTube API, i.e. explicit and localized error

@property (atomic, strong, readwrite) NSError *error;
@property (atomic, strong, readwrite) XCDYouTubeVideo *video;
@end

@implementation XCDYouTubeVideoOperation

static NSError *YouTubeError(NSError *error, NSSet *regionsAllowed, NSString *languageIdentifier)
{
	if (error.code == XCDYouTubeErrorNoStreamAvailable && regionsAllowed.count > 0)
	{
		NSLocale *locale = [NSLocale localeWithLocaleIdentifier:languageIdentifier];
		NSMutableSet *allowedCountries = [NSMutableSet new];
		for (NSString *countryCode in regionsAllowed)
		{
			NSString *country = [locale displayNameForKey:NSLocaleCountryCode value:countryCode];
			[allowedCountries addObject:country ?: countryCode];
		}
		NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:error.userInfo];
		userInfo[XCDYouTubeAllowedCountriesUserInfoKey] = [allowedCountries copy];
		return [NSError errorWithDomain:error.domain code:error.code userInfo:[userInfo copy]];
	}
	else
	{
		return error;
	}
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype) init
{
	@throw [NSException exceptionWithName:NSGenericException reason:@"Use the `initWithVideoIdentifier:cookies:languageIdentifier:` method instead." userInfo:nil];
} // LCOV_EXCL_LINE
#pragma clang diagnostic pop

- (instancetype) initWithVideoIdentifier:(NSString *)videoIdentifier languageIdentifier:(NSString *)languageIdentifier cookies:(NSArray<NSHTTPCookie *> *)cookies customPatterns:(NSArray<NSString *> *)customPatterns
{
	if (!(self = [super init]))
		return nil; // LCOV_EXCL_LINE
	
	_videoIdentifier = videoIdentifier ?: @"";
	_languageIdentifier = languageIdentifier ?: @"en";
	
	NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	_cookies = [cookies copy];
	_customPatterns = [customPatterns copy];
	
	for (NSHTTPCookie *cookie in _cookies) {
		[configuration.HTTPCookieStorage setCookie:cookie];
	}
	
	NSString *cookieValue = [NSString stringWithFormat:@"f1=50000000&f6=8&hl=%@", _languageIdentifier];
	
	NSHTTPCookie *additionalCookie = [NSHTTPCookie cookieWithProperties:@{
																		NSHTTPCookiePath: @"/",
																		NSHTTPCookieName: @"PREF",
																		NSHTTPCookieValue: cookieValue,
																		NSHTTPCookieDomain:@".youtube.com",
																		NSHTTPCookieSecure:@"TRUE"
	}];

	[configuration.HTTPCookieStorage setCookie:additionalCookie];
	configuration.HTTPAdditionalHeaders = @{@"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Safari/605.1.15"};
	_session = [NSURLSession sessionWithConfiguration:configuration];
	_operationStartSemaphore = dispatch_semaphore_create(0);
	
	return self;
}

- (instancetype) initWithVideoIdentifier:(NSString *)videoIdentifier languageIdentifier:(NSString *)languageIdentifier
{
	return [self initWithVideoIdentifier:videoIdentifier languageIdentifier:languageIdentifier cookies:nil customPatterns:nil];
}

- (instancetype) initWithVideoIdentifier:(NSString *)videoIdentifier languageIdentifier:(NSString *)languageIdentifier cookies:(NSArray<NSHTTPCookie *> *)cookies
{
	return [self initWithVideoIdentifier:videoIdentifier languageIdentifier:languageIdentifier cookies:cookies customPatterns:nil];
}


#pragma mark - Requests

- (void) startWatchPageRequest
{
	NSDictionary *query = @{ @"v": self.videoIdentifier, @"hl": self.languageIdentifier, @"has_verified": @YES, @"bpctr": @9999999999 };
	NSString *queryString = XCDQueryStringWithDictionary(query);
	NSURL *webpageURL = [NSURL URLWithString:[@"https://www.youtube.com/watch?" stringByAppendingString:queryString]];
	[self startRequestWithURL:webpageURL type:XCDYouTubeRequestTypeWatchPage];
}

- (void) startRequestWithURL:(NSURL *)url type:(XCDYouTubeRequestType)requestType
{
	if (self.isCancelled)
		return;
	
	// Downsized from original 8 which included embed page, get info requests.
	// Here we only should have two requests max: One from the start watch page and in
	// the rare case of the dash manifest request.
	if (++self.requestCount > 2)
	{
		// This condition should never happen but the request flow is quite complex so better abort here than go into an infinite loop of requests
		[self finishWithError];
		return;
	}
	
	XCDYouTubeLogDebug(@"Starting request: %@", url);
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
	[request setValue:self.languageIdentifier forHTTPHeaderField:@"Accept-Language"];
	[request setValue:[NSString stringWithFormat:@"https://youtube.com/watch?v=%@", self.videoIdentifier] forHTTPHeaderField:@"Referer"];
	
	self.dataTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		if (self.isCancelled)
			return;
		
		if (error)
			[self handleConnectionError:error requestType:requestType];
		else
			[self handleConnectionSuccessWithData:data response:response requestType:requestType];
	}];
	[self.dataTask resume];
	
	self.requestType = requestType;
}


#pragma mark - Response Dispatch

- (void) handleConnectionSuccessWithData:(NSData *)data response:(NSURLResponse *)response requestType:(XCDYouTubeRequestType)requestType
{
	CFStringEncoding encoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)response.textEncodingName ?: CFSTR(""));
	// Use kCFStringEncodingMacRoman as fallback because it defines characters for every byte value and is ASCII compatible. See https://mikeash.com/pyblog/friday-qa-2010-02-19-character-encodings.html
	NSString *responseString = CFBridgingRelease(CFStringCreateWithBytes(kCFAllocatorDefault, data.bytes, (CFIndex)data.length, encoding != kCFStringEncodingInvalidId ? encoding : kCFStringEncodingMacRoman, false)) ?: @"";

	XCDYouTubeLogVerbose(@"Response: %@\n%@", response, responseString);
	if ([(NSHTTPURLResponse *)response statusCode] == 429)
	{
		//See 429 indicates too many requests https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/429
		// This can happen when YouTube blocks the clients because of too many requests
		[self handleConnectionError:[NSError errorWithDomain:XCDYouTubeVideoErrorDomain code:XCDYouTubeErrorTooManyRequests userInfo:@{NSLocalizedDescriptionKey : @"The operation couldn’t be completed because too many requests were sent."}] requestType:requestType];
		return;
	}
	if (responseString.length == 0)
	{
		//Previously we would throw an assertion here, however, this has been changed to an error
		//See more here https://github.com/0xced/XCDYouTubeKit/issues/479
		self.lastError = [NSError errorWithDomain:XCDYouTubeVideoErrorDomain code:XCDYouTubeErrorEmptyResponse userInfo:nil];
		XCDYouTubeLogError(@"Failed to decode response from %@ (response.textEncodingName = %@, data.length = %@)", response.URL, response.textEncodingName, @(data.length));
		[self finishWithError];
		return;
	}

	switch (requestType)
	{
		case XCDYouTubeRequestTypeWatchPage:
			[self handleWebPageWithHTMLString:responseString];
			break;
		case XCDYouTubeRequestTypeDashManifest:
			[self handleDashManifestWithXMLString:responseString response:response];
			break;
	}
}

- (void) handleConnectionError:(NSError *)connectionError requestType:(XCDYouTubeRequestType)requestType
{
	// Should not return a connection error if was as a result of requesting the Dash Manifiest
	// (we have a sucessfully created `XCDYouTubeVideo` and should just finish the operation as
	// if were a 'successful' one
	if (requestType == XCDYouTubeRequestTypeDashManifest)
	{
		[self finishWithVideo:self.lastSuccessfulVideo];
		return;
	}
	
	NSDictionary *userInfo = @{	NSLocalizedDescriptionKey: connectionError.localizedDescription,
								NSUnderlyingErrorKey: connectionError };
	self.lastError = [NSError errorWithDomain:XCDYouTubeVideoErrorDomain code:XCDYouTubeErrorNetwork userInfo:userInfo];
	
	[self finishWithError];
}


#pragma mark - Response Parsing

- (void) handleWebPageWithHTMLString:(NSString *)html
{
	XCDYouTubeLogDebug(@"Handling web page response");

	self.webpage = [[XCDYouTubeVideoWebpage alloc] initWithHTMLString:html];
	[self handleVideoInfoResponseWithInfo:self.webpage.videoInfo];
}

- (void) handleVideoInfoResponseWithInfo:(NSDictionary *)info
{
	XCDYouTubeLogDebug(@"Handling video info response");

	NSError *error = nil;
	XCDYouTubeVideo *video = [[XCDYouTubeVideo alloc] initWithIdentifier:self.videoIdentifier info:info error:&error];
	if (video && video.streamURLs)
	{
		[self finishWithVideo:video];
	}
	else
	{
		self.lastSuccessfulVideo = video;

		// In the rare case we need to use the DASH Manifest to get streamURLs...
		if (info[@"streamingData"][@"dashManifestUrl"] ?: info[@"dashmpd"])
		{
			// Extract manifest's url and merge to video...
			NSURL *dashmpdURL = [NSURL URLWithString:(NSString *_Nonnull)(info[@"dashmpd"] ?: info[@"streamingData"][@"dashManifestUrl"])];
			[self startRequestWithURL:dashmpdURL type:XCDYouTubeRequestTypeDashManifest];
			return;
		}

		self.lastError = error;
		if (error.userInfo[NSLocalizedDescriptionKey])
		{
			self.youTubeError = error;
		}
		[self finishWithError];
	}
}

	// For possible use with Live videos. YouTube still uses MPEG-DASH (Dynamic Adaptive Streaming over
	// HTTP), a process that where "client side receives a manifest file, from which it chooses what
	// type of video quality will it receive, depending on the throughput the client has." Keeping this
	// in the rare case that it's the only option to obtain streamURLs.
- (void) handleDashManifestWithXMLString:(NSString *)XMLString response:(NSURLResponse *)response
{
	XCDYouTubeLogDebug(@"Handling Dash Manifest response");
	
	XCDYouTubeDashManifestXML *dashManifestXML = [[XCDYouTubeDashManifestXML alloc]initWithXMLString:XMLString];
	NSDictionary *dashManifestStreamURLs = dashManifestXML.streamURLs;
	if (dashManifestStreamURLs)
		[self.lastSuccessfulVideo mergeDashManifestStreamURLs:dashManifestStreamURLs];
	
	[self finishWithVideo:self.lastSuccessfulVideo];
}


#pragma mark - Finish Operation

- (void) finishWithVideo:(XCDYouTubeVideo *)video
{
	self.video = video;
	XCDYouTubeLogInfo(@"Video operation finished with success: %@", video);
	XCDYouTubeLogDebug(@"%@", ^{ return video.debugDescription; }());
	[self finish];
}

- (void) finishWithError
{
	self.error = self.youTubeError ? YouTubeError(self.youTubeError, self.webpage.regionsAllowed, self.languageIdentifier) : self.lastError;
	if (self.error == nil)
	{
		//This condition should never happen but as a last resort.
		//See https://github.com/0xced/XCDYouTubeKit/issues/484
		self.error = [NSError errorWithDomain:XCDYouTubeVideoErrorDomain code:XCDYouTubeErrorUnknown userInfo:@{NSLocalizedDescriptionKey : @"The operation couldn’t be completed because of an unknown error."}];
	}
	XCDYouTubeLogError(@"Video operation finished with error: %@\nDomain: %@\nCode:   %@\nUser Info: %@", self.error.localizedDescription, self.error.domain, @(self.error.code), self.error.userInfo);
	[self finish];
}

- (void) finish
{
	self.isExecuting = NO;
	self.isFinished = YES;
}


#pragma mark - NSOperation

+ (BOOL) automaticallyNotifiesObserversForKey:(NSString *)key
{
	SEL selector = NSSelectorFromString(key);
	return selector == @selector(isExecuting) || selector == @selector(isFinished) || [super automaticallyNotifiesObserversForKey:key];
}

- (BOOL) isConcurrent
{
	return YES;
}

- (void) start
{
	dispatch_semaphore_signal(self.operationStartSemaphore);
	
	if (self.isCancelled)
		return;
	
	if (self.videoIdentifier.length != 11)
	{
		XCDYouTubeLogWarning(@"Video identifier length should be 11. [%@]", self.videoIdentifier);
	}
	
	XCDYouTubeLogInfo(@"Starting video operation: %@", self);
	
	self.isExecuting = YES;
	
	self.eventLabels = [[NSMutableArray alloc] initWithArray:@[ @"embedded", @"detailpage" ]];
	[self startWatchPageRequest];
}

- (void) cancel
{
	if (self.isCancelled || self.isFinished)
		return;
	
	XCDYouTubeLogInfo(@"Canceling video operation: %@", self);
	
	[super cancel];
	
	[self.dataTask cancel];
	
	// Wait for `start` to be called in order to avoid this warning: *** XCDYouTubeVideoOperation 0x7f8b18c84880 went isFinished=YES without being started by the queue it is in
	dispatch_semaphore_wait(self.operationStartSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)));
	[self finish];
}

#pragma mark - NSObject

- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@: %p> %@ (%@)", self.class, self, self.videoIdentifier, self.languageIdentifier];
}

@end
