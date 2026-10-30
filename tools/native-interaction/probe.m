#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdio.h>

// A simulator-only observer. It does not change selection, dispatch actions,
// synthesize touches, or modify layers/materials.
static FILE *output;
static CFTimeInterval started;
static void (*originalSendEvent)(UIApplication *, SEL, UIEvent *);
static NSArray *fullFilterKeys;
static void snapshot(NSString *name);

static id jsonValue(id value) {
    if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSData.class]) return @{@"type": @"data", @"base64": [value base64EncodedStringWithOptions:0]};
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in value) [items addObject:jsonValue(item)];
        return items;
    }
    return [value description] ?: @"";
}

static NSDictionary *effectValues(id object) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    Class cls = [object class];
    while (cls && cls != NSObject.class && cls != CALayer.class) {
        unsigned count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        for (unsigned index = 0; index < count; ++index) {
            NSString *key = @(property_getName(properties[index]));
            @try {
                id value = [object valueForKey:key];
                if (value) result[key] = jsonValue(value);
            } @catch (NSException *exception) { (void)exception; }
        }
        free(properties);
        cls = class_getSuperclass(cls);
    }
    return result;
}

static NSArray *point(CGPoint value) { return @[@(value.x), @(value.y)]; }
static NSArray *rect(CGRect value) {
    return @[@(value.origin.x), @(value.origin.y), @(value.size.width), @(value.size.height)];
}
static NSString *identity(id object) { return [NSString stringWithFormat:@"%p", object]; }

static void emit(NSDictionary *value) {
    if (!output) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, output);
    fputc('\n', output);
    fflush(output);
}

static NSString *phase(UITouchPhase value) {
    switch (value) {
        case UITouchPhaseBegan: return @"began";
        case UITouchPhaseMoved: return @"moved";
        case UITouchPhaseStationary: return @"stationary";
        case UITouchPhaseEnded: return @"ended";
        case UITouchPhaseCancelled: return @"cancelled";
        default: return [NSString stringWithFormat:@"%ld", (long)value];
    }
}

static void observeEvent(UIApplication *application, SEL command, UIEvent *event) {
    for (UITouch *touch in event.allTouches) {
        emit(@{
            @"kind": @"touch", @"t": @(CACurrentMediaTime() - started),
            @"eventTime": @(touch.timestamp), @"id": identity(touch),
            @"phase": phase(touch.phase), @"location": point([touch locationInView:touch.window]),
            @"previous": point([touch previousLocationInView:touch.window]),
            @"view": NSStringFromClass(touch.view.class) ?: @"", @"force": @(touch.force)
        });
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            NSString *name = phase(touch.phase);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ snapshot(name); });
        }
    }
    originalSendEvent(application, command, event);
}

static UITabBar *tabBar(UIView *view) {
    if ([view isKindOfClass:UITabBar.class]) return (UITabBar *)view;
    for (UIView *child in view.subviews) {
        UITabBar *result = tabBar(child);
        if (result) return result;
    }
    return nil;
}

static NSArray *filters(CALayer *layer, BOOL full) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in @[@"filters", @"backgroundFilters", @"compositingFilter"]) {
        @try {
            id value = [layer valueForKey:key];
            if (!value) continue;
            for (id filter in [value isKindOfClass:NSArray.class] ? value : @[value]) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"slot"] = key;
                entry[@"name"] = [filter valueForKey:@"name"] ?: NSStringFromClass([filter class]);
                NSArray *keys = full ? fullFilterKeys : @[@"inputAmount", @"inputInnerRefractionAmount",
                     @"inputOuterRefractionAmount", @"inputRefractionOpacity", @"inputBlurRadius"];
                for (NSString *input in keys) {
                    @try {
                        id parameter = [filter valueForKey:input];
                        if (parameter && (full || [parameter isKindOfClass:NSNumber.class])) entry[input] = jsonValue(parameter);
                    } @catch (NSException *exception) { (void)exception; }
                }
                [result addObject:entry];
            }
        } @catch (NSException *exception) { (void)exception; }
    }
    return result;
}

static void layers(CALayer *layer, CALayer *root, NSMutableArray *result, BOOL full, NSUInteger depth) {
    if (depth > 24 || result.count >= 256) return;
    CALayer *visible = layer.presentationLayer ?: layer;
    CATransform3D a = visible.transform;
    NSMutableDictionary *entry = [@{
        @"id": identity(layer), @"parent": identity(layer.superlayer), @"depth": @(depth),
        @"class": NSStringFromClass(layer.class), @"name": layer.name ?: @"",
        @"delegate": layer.delegate ? NSStringFromClass([layer.delegate class]) : @"",
        @"presentation": @(layer.presentationLayer != nil),
        @"frame": rect(visible.frame), @"bounds": rect(visible.bounds),
        @"position": point(visible.position), @"anchor": point(visible.anchorPoint),
        @"screenRect": rect([visible convertRect:visible.bounds toLayer:root]),
        @"modelFrame": rect(layer.frame), @"opacity": @(visible.opacity),
        @"cornerRadius": @(visible.cornerRadius), @"masksToBounds": @(layer.masksToBounds),
        @"transform": @[@(a.m11), @(a.m12), @(a.m13), @(a.m14),
                        @(a.m21), @(a.m22), @(a.m23), @(a.m24),
                        @(a.m31), @(a.m32), @(a.m33), @(a.m34),
                        @(a.m41), @(a.m42), @(a.m43), @(a.m44)],
        @"filters": filters(visible, full)
    } mutableCopy];
    if (full) entry[@"modelFilters"] = filters(layer, YES);
    @try {
        id effect = [visible valueForKey:@"effect"];
        if (effect) {
            entry[@"effect"] = NSStringFromClass([effect class]);
            if (full) entry[@"effectValues"] = effectValues(effect);
            for (NSString *key in @[@"height", @"curvature", @"angle", @"maskOffset", @"effectOffset"]) {
                @try {
                    id value = [effect valueForKey:key];
                    if ([value isKindOfClass:NSNumber.class]) entry[key] = value;
                } @catch (NSException *exception) { (void)exception; }
            }
        }
    } @catch (NSException *exception) { (void)exception; }
    [result addObject:entry];
    for (CALayer *child in layer.sublayers) layers(child, root, result, full, depth + 1);
}

static void snapshot(NSString *name) {
    if (!output) return;
    static NSUInteger sequence = 0;
    NSMutableArray *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NSMutableArray *items = [NSMutableArray array];
            layers(window.layer, window.layer.presentationLayer ?: window.layer, items, YES, 0);
            [windows addObject:@{@"style": @(window.traitCollection.userInterfaceStyle), @"layers": items}];
        }
    }
    NSDictionary *value = @{@"kind": @"materials", @"phase": name,
        @"t": @(CACurrentMediaTime() - started), @"windows": windows,
        @"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()),
        @"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()),
        @"increaseContrast": @(UIAccessibilityDarkerSystemColorsEnabled())};
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/interaction"];
    NSString *filename = [NSString stringWithFormat:@"%02lu-%@.json", (unsigned long)sequence++, name];
    [data writeToFile:[directory stringByAppendingPathComponent:filename] atomically:YES];
    emit(@{@"kind": @"snapshot", @"t": value[@"t"], @"file": filename});
}

@interface TabsterInteractionObserver : NSObject
@property(nonatomic, strong) CADisplayLink *displayLink;
@end

@implementation TabsterInteractionObserver
- (void)sample:(CADisplayLink *)link {
    if (CACurrentMediaTime() - started > 20) {
        [link invalidate];
        self.displayLink = nil;
        if (output) { fclose(output); output = NULL; }
        return;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UITabBar *bar = tabBar(window);
            if (!bar) continue;
            NSMutableArray *samples = [NSMutableArray array];
            layers(bar.layer, window.layer.presentationLayer ?: window.layer, samples, NO, 0);
            emit(@{@"kind": @"frame", @"t": @(CACurrentMediaTime() - started),
                   @"displayTime": @(link.timestamp), @"style": @(window.traitCollection.userInterfaceStyle),
                   @"layers": samples});
        }
    }
}
@end

__attribute__((constructor)) static void install(void) {
    if (![NSProcessInfo.processInfo.environment[@"TABSTER_INTERACTION_PROBE"] isEqualToString:@"1"]) return;
    started = CACurrentMediaTime();
    fullFilterKeys = @[
#include "../native-materials/input-keys.inc"
    ];
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/interaction"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    output = fopen([directory stringByAppendingPathComponent:@"interaction.jsonl"].fileSystemRepresentation, "w");
    emit(@{@"kind": @"environment", @"t": @0,
           @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
           @"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()),
           @"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()),
           @"increaseContrast": @(UIAccessibilityDarkerSystemColorsEnabled())});
    Method method = class_getInstanceMethod(UIApplication.class, @selector(sendEvent:));
    originalSendEvent = (void (*)(UIApplication *, SEL, UIEvent *))method_setImplementation(method, (IMP)observeEvent);
    dispatch_async(dispatch_get_main_queue(), ^{
        static TabsterInteractionObserver *observer;
        observer = [TabsterInteractionObserver new];
        observer.displayLink = [CADisplayLink displayLinkWithTarget:observer selector:@selector(sample:)];
        observer.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        [observer.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ snapshot(@"initial"); });
    });
}
