#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Loaded only into the simulator by the reference workflow. The guest binary
// is unchanged. This records numeric material/layout/animation data, not pixels.
static NSArray *filterKeys;

static void values(id object, NSArray *keys, NSMutableString *report) {
    for (NSString *key in keys) {
        @try {
            id value = [object valueForKey:key];
            if (value) [report appendFormat:@"  %@ = %@\n", key, value];
        } @catch (NSException *exception) { (void)exception; }
    }
}

static void properties(id object, NSMutableString *report) {
    NSMutableSet *keys = [NSMutableSet set];
    Class cls = object_getClass(object);
    SEL defaults = sel_registerName("defaultValues");
    if ([cls respondsToSelector:defaults]) {
        id dictionary = ((id (*)(id, SEL))objc_msgSend)(cls, defaults);
        if ([dictionary isKindOfClass:NSDictionary.class]) [keys addObjectsFromArray:[dictionary allKeys]];
    }
    while (cls && cls != CALayer.class && cls != NSObject.class) {
        unsigned count = 0;
        objc_property_t *list = class_copyPropertyList(cls, &count);
        for (unsigned index = 0; index < count; ++index) {
            [keys addObject:@(property_getName(list[index]))];
        }
        free(list);
        cls = class_getSuperclass(cls);
    }
    values(object, [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)], report);
}

static void layer(CALayer *item, NSMutableString *report, NSUInteger depth) {
    if (depth > 32) return;
    [report appendFormat:@"LAYER %lu %@ frame=%@ opacity=%g\n", (unsigned long)depth,
        NSStringFromClass(item.class), NSStringFromCGRect(item.frame), item.opacity];
    values(item, @[@"backgroundColor", @"cornerRadius", @"cornerCurve", @"effectOffset", @"smoothness", @"gaussianRadius", @"mode", @"gradientOvalization"], report);
    @try {
        id effect = [item valueForKey:@"effect"];
        if (effect) { [report appendFormat:@"EFFECT %@\n", effect]; properties(effect, report); }
    } @catch (NSException *exception) { (void)exception; }
    for (NSString *key in @[@"filters", @"backgroundFilters", @"compositingFilter"]) {
        @try {
            id value = [item valueForKey:key];
            if (!value) continue;
            for (id filter in [value isKindOfClass:NSArray.class] ? value : @[value]) {
                [report appendFormat:@"FILTER %@ %@\n", key, filter];
                values(filter, filterKeys, report);
            }
        } @catch (NSException *exception) { (void)exception; }
    }
    for (NSString *key in item.animationKeys) {
        CAAnimation *animation = [item animationForKey:key];
        [report appendFormat:@"ANIMATION %@ %@\n", key, animation];
        values(animation, @[@"duration", @"beginTime", @"timingFunction", @"mass", @"stiffness", @"damping", @"initialVelocity", @"keyPath", @"fromValue", @"toValue"], report);
    }
    for (CALayer *child in item.sublayers) layer(child, report, depth + 1);
}

static void writeReport(NSString *name) {
    NSMutableString *report = [NSMutableString string];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) layer(window.layer, report, 0);
    }
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/materials"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [report writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static UIControl *secondTab(UIView *view, NSUInteger *index) {
    if ([NSStringFromClass(view.class) isEqualToString:@"_UITabButton"]) {
        if ((*index)++ == 1) return (UIControl *)view;
    }
    for (UIView *child in view.subviews) {
        UIControl *match = secondTab(child, index);
        if (match) return match;
    }
    return nil;
}

__attribute__((constructor)) static void install(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        filterKeys = [[NSString stringWithContentsOfFile:@"/tmp/tabster-filter-keys.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"];
        writeReport(@"settled.txt");
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                NSUInteger index = 0;
                UIControl *tab = secondTab(window.rootViewController.view, &index);
                [tab sendActionsForControlEvents:UIControlEventTouchDown];
                [tab sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 60), dispatch_get_main_queue(), ^{ writeReport(@"transition.txt"); });
    });
}
