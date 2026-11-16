//
//  ADMainDataSource.h
//  AppData
//
//  Created by Fouad Raheb on 7/15/20.
//

#import <Foundation/Foundation.h>

@class ADDataViewController;
@class ADAppData;

@interface ADMainDataSource : NSObject <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) ADAppData *appData;
@property (nonatomic, weak) ADDataViewController *dataViewController;

- (instancetype)initWithAppData:(ADAppData *)data dataViewController:(ADDataViewController *)dataViewController;

@end
