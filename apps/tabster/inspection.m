#import <UIKit/UIKit.h>
#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
static void inspectLayer(CALayer *layer, NSMutableString *report, NSUInteger depth) {
    if (depth > 24) return;
    [report appendFormat:@"LAYER depth=%lu class=%@ frame=%@ bounds=%@ radius=%g\n",
        (unsigned long)depth, NSStringFromClass(layer.class), NSStringFromCGRect(layer.frame),
        NSStringFromCGRect(layer.bounds), layer.cornerRadius];
    for (NSString *property in @[@"filters", @"backgroundFilters", @"compositingFilter"]) {
        @try {
            id value = [layer valueForKey:property];
            if (!value) continue;
            NSArray *filters = [value isKindOfClass:NSArray.class] ? value : @[value];
            for (id filter in filters) {
                [report appendFormat:@"FILTER %@ %@\n", property, filter];
                @try {
                    for (NSString *key in [filter valueForKey:@"inputKeys"]) {
                        [report appendFormat:@"  %@ = %@\n", key, [filter valueForKey:key]];
                    }
                } @catch (NSException *exception) {
                    [report appendFormat:@"  reflection = %@\n", exception.reason];
                }
            }
        } @catch (NSException *exception) { (void)exception; }
    }
    for (CALayer *child in layer.sublayers) inspectLayer(child, report, depth + 1);
}

static void inspectViews(UIView *view, UITabBar *bar, CGContextRef context,
                         NSMutableString *report, NSUInteger depth) {
    if (depth > 24 || view.hidden || view.alpha == 0) return;
    CGRect frame = [view convertRect:view.bounds toView:bar];
    [report appendFormat:@"VIEW depth=%lu class=%@ frame=%@\n", (unsigned long)depth,
        NSStringFromClass(view.class), NSStringFromCGRect(frame)];
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        [report appendFormat:@"LABEL text=%@ font=%@ size=%g color=%@\n",
            label.text, label.font.fontName, label.font.pointSize, label.textColor];
    }
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class]) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, frame.origin.x, frame.origin.y);
        [view.layer renderInContext:context];
        CGContextRestoreGState(context);
        return;
    }
    for (UIView *child in view.subviews) inspectViews(child, bar, context, report, depth + 1);
}

void inspectTabster(UITabBarController *tabs, UIWindow *window) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/reference"];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSMutableString *report = [NSMutableString stringWithFormat:@"WINDOW %@ safeArea=%@ scale=%g\nTAB %@ bounds=%@\n",
            NSStringFromCGRect(window.bounds), NSStringFromUIEdgeInsets(window.safeAreaInsets), window.screen.scale,
            NSStringFromCGRect(tabs.tabBar.frame), NSStringFromCGRect(tabs.tabBar.bounds)];
        inspectLayer(tabs.tabBar.layer, report, 0);
        [UIView setAnimationsEnabled:NO];
        for (NSUInteger selected = 0; selected < 3; ++selected) {
            tabs.selectedIndex = selected;
            [tabs.view layoutIfNeeded];
            [CATransaction flush];
            [report appendFormat:@"STATE %lu\n", (unsigned long)selected];
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = 3;
            format.opaque = NO;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:tabs.tabBar.bounds.size format:format];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                inspectViews(tabs.tabBar, tabs.tabBar, context.CGContext, report, 0);
            }];
            NSString *name = [NSString stringWithFormat:@"foreground-%lu.png", (unsigned long)selected];
            [UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES];
            [renderer release];
        }
        tabs.selectedIndex = 0;
        [UIView setAnimationsEnabled:YES];
        [report writeToFile:[directory stringByAppendingPathComponent:@"layers.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    });
}
#endif
