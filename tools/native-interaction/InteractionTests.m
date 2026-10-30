#import <XCTest/XCTest.h>

@interface NativeInteractionTests : XCTestCase
@end

@implementation NativeInteractionTests

- (void)testHeldTabDrag {
    self.continueAfterFailure = NO;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"org.lstudio.apple.Tabster"];
    app.launchEnvironment = @{
        @"DYLD_INSERT_LIBRARIES": @"/tmp/tabster-interaction.dylib",
        @"TABSTER_INTERACTION_PROBE": @"1"
    };
    [app launch];
    XCTAssertTrue([app.windows.firstMatch waitForExistenceWithTimeout:10]);
    CGRect frame = app.frame;
    XCTAssertEqualWithAccuracy(frame.size.width, 390, 0.5);
    XCTAssertEqualWithAccuracy(frame.size.height, 844, 0.5);
    XCUICoordinate *origin = [app coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
    XCUICoordinate *first = [origin coordinateWithOffset:CGVectorMake(109, 792)];
    XCUICoordinate *last = [origin coordinateWithOffset:CGVectorMake(281, 792)];
    // This endpoint lies between tab centers. The held interval distinguishes
    // continuous following from movement to a discrete selected tab center.
    XCUICoordinate *between = [origin coordinateWithOffset:CGVectorMake(152, 792)];
    XCUICoordinate *betweenLast = [origin coordinateWithOffset:CGVectorMake(238, 792)];
    [NSThread sleepForTimeInterval:2];
    [first pressForDuration:1 thenDragToCoordinate:betweenLast withVelocity:60 thenHoldForDuration:1];
    [NSThread sleepForTimeInterval:0.5];
    [last pressForDuration:0.5 thenDragToCoordinate:between withVelocity:60 thenHoldForDuration:1];
    [NSThread sleepForTimeInterval:1];
    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    attachment.name = @"released";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
    XCTAssertEqual(app.state, XCUIApplicationStateRunningForeground);
}

@end
