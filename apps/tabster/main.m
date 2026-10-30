/*
 * Copyright (C) 2018 Apple Inc. All Rights Reserved.
 * See LICENSE.txt for the original Tabster sample's licensing information.
 *
 * Cropped from Tabster's AppDelegate / FourViewController tab setup. The
 * storyboard, navigation, restoration and badge examples are removed. Delegates
 * are registered dynamically for apple-runtime's existing Objective-C bridge.
 */
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *string(const char *value) {
    return [NSString stringWithUTF8String:value];
}

static BOOL launched(id self, SEL command, UIApplication *app, NSDictionary *options) {
    (void)self; (void)command; (void)app; (void)options;
    return YES;
}

static UISceneConfiguration *configuration(id self, SEL command, UIApplication *app,
                                           UISceneSession *session, UISceneConnectionOptions *options) {
    (void)self; (void)command; (void)app; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc]
        initWithName:string("Tabster") sessionRole:session.role];
    configuration.delegateClass = objc_getClass("TabsterSceneDelegate");
    return configuration;
}

static void connect_scene(id self, SEL command, UIWindowScene *scene,
                          UISceneSession *session, UISceneConnectionOptions *options) {
    (void)self; (void)command; (void)session; (void)options;
    CGRect bounds = scene.coordinateSpace.bounds;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    UITabBarController *tabs = [[UITabBarController alloc] init];
    UIViewController *controllers[3];
    const char *titles[3] = {"Explore", "Favorites", "Library"};
    const char *symbols[3] = {"globe.europe.africa.fill", "star.fill", "books.vertical.fill"};
    const CGFloat colors[3][3] = {{0.07, 0.42, 0.68}, {0.66, 0.22, 0.42}, {0.17, 0.49, 0.35}};

    for (NSUInteger page = 0; page < 3; ++page) {
        UIViewController *controller = [[UIViewController alloc] init];
        controller.tabBarItem = [[UITabBarItem alloc]
            initWithTitle:string(titles[page]) image:[UIImage systemImageNamed:string(symbols[page])] tag:page];
        controller.view.backgroundColor = [UIColor whiteColor];

        // Content deliberately extends behind the system tab bar. Alternating
        // colored bands and text expose backdrop blur, refraction and tint.
        for (NSUInteger row = 0; row < 14; ++row) {
            CGFloat y = row * bounds.size.height / 14;
            UIView *band = [[UIView alloc] initWithFrame:CGRectMake(0, y, bounds.size.width, bounds.size.height / 14 + 1)];
            CGFloat amount = (row % 3) * 0.14;
            band.backgroundColor = [UIColor colorWithRed:colors[page][0] + amount
                green:colors[page][1] + amount blue:colors[page][2] + amount alpha:1];
            [controller.view addSubview:band];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(18, 0, bounds.size.width - 36, bounds.size.height / 14)];
            label.text = string(row == 0 ? "APPLE TABSTER" : row > 10 ? "CONTENT BEHIND THE GLASS" : titles[page]);
            label.textColor = [UIColor whiteColor];
            [band addSubview:label];
        }
        controllers[page] = controller;
    }
    tabs.viewControllers = [NSArray arrayWithObjects:controllers count:3];
    window.rootViewController = tabs;
    [window makeKeyAndVisible];
}

int main(int argc, char **argv) {
    Class app = objc_allocateClassPair([NSObject class], "TabsterAppDelegate", 0);
    class_addProtocol(app, objc_getProtocol("UIApplicationDelegate"));
    class_addMethod(app, sel_registerName("application:didFinishLaunchingWithOptions:"), (IMP)launched, "B@:@@");
    class_addMethod(app, sel_registerName("application:configurationForConnectingSceneSession:options:"), (IMP)configuration, "@@:@@@");
    objc_registerClassPair(app);
    Class scene = objc_allocateClassPair([NSObject class], "TabsterSceneDelegate", 0);
    class_addProtocol(scene, objc_getProtocol("UIWindowSceneDelegate"));
    class_addMethod(scene, sel_registerName("scene:willConnectToSession:options:"), (IMP)connect_scene, "v@:@@@");
    objc_registerClassPair(scene);
    return UIApplicationMain(argc, argv, nil, string("TabsterAppDelegate"));
}
