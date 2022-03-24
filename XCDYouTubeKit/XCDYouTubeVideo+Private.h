//
//  Copyright (c) 2013-2016 Cédric Luthi. All rights reserved.
//

#import "XCDYouTubeVideo.h"

#define XCDYouTubeErrorUseCipherSignature -1000

extern NSString *const XCDYouTubeNoStreamVideoUserInfoKey;

extern NSDictionary *XCDDictionaryWithQueryString(NSString *string);
extern NSString *XCDQueryStringWithDictionary(NSDictionary *dictionary);
extern NSArray *XCDThumbnailArrayWithString(NSString *string);
extern NSString *XCDHTTPLiveStreamingStringWithString(NSString *string);
extern NSDictionary *XCDDictionaryWithString(NSString *string);
extern NSDictionary *XCDStreamingDataWithString(NSString *string);

@interface XCDYouTubeVideo ()

- (instancetype) initWithIdentifier:(NSString *)identifier info:(NSDictionary *)info error:(NSError **)error;

- (void) mergeVideo:(XCDYouTubeVideo *)video;
- (void) mergeDashManifestStreamURLs:(NSDictionary *)dashManifestStreamURLs;

@end
