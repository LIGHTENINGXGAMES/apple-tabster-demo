/*
 Copyright (C) 2018 Apple Inc. All Rights Reserved.
  See LICENSE.txt for this sample’s licensing information
  
  Abstract:
  The view controller for page four. 
 */

#import "FourViewController.h"

@interface FourViewController ()

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@end

#pragma mark -

@implementation FourViewController

- (void)awakeFromNib
{
	[super awakeFromNib];
	
	// Make our tabbar icon a custom one;
	// we could do it in Interface Builder, but this is just to illustrate a point about
	// using awakeFromNib vs. viewDidLoad.
	//
	UITabBarItem *customTab = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Four", @"")
															image:[UIImage imageNamed:@"tab4.png"]
															  tag:0];
	self.tabBarItem = customTab;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	// If we were navigated to through the More screen table, then we have a navigation bar which
	// also means we have a title.  So hide the title label in this case, otherwise, we need it.
	//
	self.titleLabel.hidden = [self.parentViewController isKindOfClass:[UINavigationController class]] ? YES : NO;
}

@end
