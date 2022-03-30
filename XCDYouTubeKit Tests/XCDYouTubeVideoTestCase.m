//
//  Copyright (c) 2013-2016 Cédric Luthi. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "XCDYouTubeVideo+Private.h"
#import "XCDYouTubeError.h"

@interface XCDYouTubeVideoTestCase : XCTestCase
@end

@implementation XCDYouTubeVideoTestCase

- (void) testVideoEquality
{
	XCDYouTubeVideo *videoA = [[XCDYouTubeVideo alloc] initWithIdentifier:@"videoA" info:@{ @"url_encoded_fmt_stream_map": @"url=http://www.youtube.com/videoA.mp4&itag=123"} error:NULL];
	XCDYouTubeVideo *videoB = [[XCDYouTubeVideo alloc] initWithIdentifier:@"videoB" info:@{ @"url_encoded_fmt_stream_map": @"url=http://www.youtube.com/videoB.mp4&itag=123"} error:NULL];
	
	XCTAssertEqualObjects(videoA.identifier, @"videoA");
	XCTAssertEqualObjects(videoB.identifier, @"videoB");
	XCTAssertNotEqualObjects(videoA, videoB);
	XCTAssertNotEqualObjects(videoA, [NSDate date]);
}

- (void) testVideoAsKeyInDictionary
{
	XCDYouTubeVideo *videoA = [[XCDYouTubeVideo alloc] initWithIdentifier:@"videoA" info:@{ @"url_encoded_fmt_stream_map": @"url=http://www.youtube.com/videoA.mp4&itag=123"} error:NULL];
	XCTAssertNoThrow(@{ videoA: @5 });
}

@end
