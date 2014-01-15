//
//  TTStandardVersionComparator.h
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#ifndef TTSTANDARDVERSIONCOMPARATOR_H
#define TTSTANDARDVERSIONCOMPARATOR_H


#import "TTVersionComparisonProtocol.h"

/*!
    @class
    @abstract    Sparkle's default version comparator.
  @discussion  This comparator is adapted from MacPAD, by Kevin Ballard. It's "dumb" in that it does essentially string comparison, in components split by
  character type.
*/
@interface TTStandardVersionComparator : NSObject<TTVersionComparison> {
}

/*!
    @method
    @abstract   Returns a singleton instance of the comparator.
*/
+ (TTStandardVersionComparator*)defaultComparator;

/*!
  @method
  @abstract	Compares version strings through textual analysis.
  @discussion	See the implementation for more details.
*/
- (NSComparisonResult)compareVersion:(NSString*)versionA toVersion:(NSString*)versionB;
@end

#endif
