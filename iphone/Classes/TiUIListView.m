/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2013-2015 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#ifdef USE_TI_UILISTVIEW

#import "TiUIListView.h"
#import "TiUIListSectionProxy.h"
#import "TiUIListItem.h"
#import "TiUIListItemProxy.h"
#import "TiUILabelProxy.h"
#import "TiUISearchBarProxy.h"
#ifdef USE_TI_UIREFRESHCONTROL
#import "TiUIRefreshControlProxy.h"
#endif
#import "ImageLoader.h"

@interface TiUIListView ()
@property (nonatomic, readonly) TiUIListViewProxy *listViewProxy;
@property (nonatomic,copy,readwrite) NSString * searchString;
@end

static TiViewProxy * FindViewProxyWithBindIdContainingPoint(UIView *view, CGPoint point);

@implementation TiUIListView {
    UITableView *_tableView;
    NSDictionary *_templates;
    id _defaultItemTemplate;

    TiDimension _rowHeight;
    TiViewProxy *_headerViewProxy;
    TiViewProxy *_searchWrapper;
    TiViewProxy *_headerWrapper;
    TiViewProxy *_footerViewProxy;
    TiViewProxy *_pullViewProxy;
#ifdef USE_TI_UIREFRESHCONTROL
    TiUIRefreshControlProxy* _refreshControlProxy;
#endif

    TiUISearchBarProxy *searchViewProxy;
    UITableViewController *tableController;
    UISearchDisplayController *searchController;

    NSMutableArray * sectionTitles;
    NSMutableArray * sectionIndices;
    NSMutableArray * filteredTitles;
    NSMutableArray * filteredIndices;

    UIView *_pullViewWrapper;
    CGFloat pullThreshhold;

    BOOL pullActive;
    CGPoint tapPoint;
    BOOL editing;
    BOOL pruneSections;
    
    BOOL caseInsensitiveSearch;
    NSString* _searchString;
    BOOL searchActive;
    BOOL keepSectionsInSearch;
    NSMutableArray* _searchResults;
    UIEdgeInsets _defaultSeparatorInsets;
    
    NSMutableDictionary* _measureProxies;
    
    BOOL canFireScrollStart;
    BOOL canFireScrollEnd;
    BOOL isScrollingToTop;
    
    BOOL bReverseMode;
    BOOL isBottom;
    int nInsertItemCount;
}

- (id)init
{
    self = [super init];
    if (self) {
        canFireScrollEnd = NO;
        canFireScrollStart = YES;
        _defaultItemTemplate = [[NSNumber numberWithUnsignedInteger:UITableViewCellStyleDefault] retain];
        _defaultSeparatorInsets = UIEdgeInsetsZero;
        
        bReverseMode = false;
        isBottom = true;
        nInsertItemCount = 0;
    }
    return self;
}

- (void)dealloc
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [_tableView release];
    [_templates release];
    [_defaultItemTemplate release];
    [_headerViewProxy setProxyObserver:nil];
    [_footerViewProxy setProxyObserver:nil];
    [_pullViewProxy setProxyObserver:nil];
    RELEASE_TO_NIL(_searchString);
    RELEASE_TO_NIL(_searchResults);
    RELEASE_TO_NIL(_pullViewWrapper);
    RELEASE_TO_NIL(_pullViewProxy);
    RELEASE_TO_NIL(_headerViewProxy);
    RELEASE_TO_NIL(_searchWrapper);
    RELEASE_TO_NIL(_headerWrapper)
    RELEASE_TO_NIL(_footerViewProxy);
    RELEASE_TO_NIL(searchViewProxy);
    RELEASE_TO_NIL(tableController);
    RELEASE_TO_NIL(searchController);
    RELEASE_TO_NIL(sectionTitles);
    RELEASE_TO_NIL(sectionIndices);
    RELEASE_TO_NIL(filteredTitles);
    RELEASE_TO_NIL(filteredIndices);
    RELEASE_TO_NIL(_measureProxies);
#ifdef USE_TI_UIREFRESHCONTROL
    RELEASE_TO_NIL(_refreshControlProxy);
#endif
    [super dealloc];
}

-(void)setReverseMode:(bool)bMode
{
    bReverseMode = bMode;
}

-(void)setBottomState:(bool)bState
{
    isBottom = bState;
}

-(void)setInsertItemCount:(int)count
{
    nInsertItemCount = count;
}

-(TiViewProxy*)initWrapperProxy
{
    TiViewProxy* theProxy = [[TiViewProxy alloc] init];
    LayoutConstraint* viewLayout = [theProxy layoutProperties];
    viewLayout->width = TiDimensionAutoFill;
    viewLayout->height = TiDimensionAutoSize;
    return theProxy;
}

-(void)setHeaderFooter:(TiViewProxy*)theProxy isHeader:(BOOL)header
{
    [theProxy setProxyObserver:self];
    if (header) {
        [self.tableView setTableHeaderView:[theProxy view]];
    } else {
        [self.tableView setTableFooterView:[theProxy view]];
    }
    [theProxy windowWillOpen];
    [theProxy setParentVisible:YES];
    [theProxy windowDidOpen];
}

-(void)configureFooter
{
    if (_footerViewProxy == nil) {
        _footerViewProxy = [self initWrapperProxy];
        [self setHeaderFooter:_footerViewProxy isHeader:NO];
    }
    
}

-(void)configureHeaders
{
    _headerViewProxy = [self initWrapperProxy];
    LayoutConstraint* viewLayout = [_headerViewProxy layoutProperties];
    viewLayout->layoutStyle = TiLayoutRuleVertical;
    [self setHeaderFooter:_headerViewProxy isHeader:YES];
    
    _searchWrapper = [self initWrapperProxy];
    _headerWrapper = [self initWrapperProxy];

    [_headerViewProxy add:_searchWrapper];
    [_headerViewProxy add:_headerWrapper];
    
}

- (UITableView *)tableView
{
    if (_tableView == nil) {
        UITableViewStyle style = [TiUtils intValue:[self.proxy valueForKey:@"style"] def:UITableViewStylePlain];

        _tableView = [[UITableView alloc] initWithFrame:self.bounds style:style];
        _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _tableView.delegate = self;
        _tableView.dataSource = self;

        if (TiDimensionIsDip(_rowHeight)) {
            [_tableView setRowHeight:_rowHeight.value];
        }
        id backgroundColor = [self.proxy valueForKey:@"backgroundColor"];
        BOOL doSetBackground = YES;
        if (style == UITableViewStyleGrouped) {
            doSetBackground = (backgroundColor != nil);
        }
        if (doSetBackground) {
            [[self class] setBackgroundColor:[TiUtils colorValue:backgroundColor] onTable:_tableView];
        }
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tapGestureRecognizer.delegate = self;
        [_tableView addGestureRecognizer:tapGestureRecognizer];
        [tapGestureRecognizer release];

        [self configureHeaders];
        _defaultSeparatorInsets = [_tableView separatorInset];
        
        if ([TiUtils isIOS8OrGreater]) {
            [_tableView setLayoutMargins:UIEdgeInsetsZero];
        }
        
    }
    if ([_tableView superview] != self) {
        [self addSubview:_tableView];
    }
    return _tableView;
}

-(void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
    if (![searchController isActive]) {
        [searchViewProxy ensureSearchBarHeirarchy];
        if (_searchWrapper != nil) {
            CGFloat rowWidth = [self computeRowWidth:_tableView];
            if (rowWidth > 0) {
                CGFloat right = _tableView.bounds.size.width - rowWidth;
                [_searchWrapper layoutProperties]->right = TiDimensionDip(right);
            }
        }
    } else {
        [_tableView reloadData];
    }
    [super frameSizeChanged:frame bounds:bounds];
    
    if (_headerViewProxy != nil) {
        [_headerViewProxy parentSizeWillChange];
    }
    if (_footerViewProxy != nil) {
        [_footerViewProxy parentSizeWillChange];
    }
    if (_pullViewWrapper != nil) {
        _pullViewWrapper.frame = CGRectMake(0.0f, 0.0f - bounds.size.height, bounds.size.width, bounds.size.height);
        [_pullViewProxy parentSizeWillChange];
    }
    
    if ( bReverseMode == true )
    {
    	//DebugLog(@"----[INFO] ListView : getBottomState = %d", isBottom);
    	if (isBottom == true)
    	{
	        if ( _tableView != nil && [_tableView numberOfSections] > 0 && [_tableView numberOfRowsInSection:0] > 0)
	        {
                [_tableView beginUpdates];
                NSIndexPath *scrollIndexPath = [NSIndexPath indexPathForRow:[_tableView numberOfRowsInSection:0]-1 inSection:0];
                //DebugLog(@"----[INFO] ListView : tableView Count = %d, indexPath = %@", [_tableView numberOfRowsInSection:0], scrollIndexPath.debugDescription);
                if ( scrollIndexPath != nil )
                    [_tableView scrollToRowAtIndexPath:scrollIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:NO];
                [_tableView endUpdates];
	        }
    	}
    }
}

- (id)accessibilityElement
{
	return self.tableView;
}

- (TiUIListViewProxy *)listViewProxy
{
	return (TiUIListViewProxy *)self.proxy;
}

- (void)deselectAll:(BOOL)animated
{
	if (_tableView != nil) {
		[_tableView.indexPathsForSelectedRows enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, NSUInteger idx, BOOL *stop) {
			[_tableView deselectRowAtIndexPath:indexPath animated:animated];
		}];
	}
}

- (void) updateIndicesForVisibleRows
{
    if (_tableView == nil || [self isSearchActive]) {
        return;
    }
    
    NSArray* visibleRows = [_tableView indexPathsForVisibleRows];
    [visibleRows enumerateObjectsUsingBlock:^(NSIndexPath *vIndexPath, NSUInteger idx, BOOL *stop) {
        UITableViewCell* theCell = [_tableView cellForRowAtIndexPath:vIndexPath];
        if ([theCell isKindOfClass:[TiUIListItem class]]) {
            ((TiUIListItem*)theCell).proxy.indexPath = vIndexPath;
            [((TiUIListItem*)theCell) ensureVisibleSelectorWithTableView:_tableView];
        }
    }];
}

-(void)proxyDidRelayout:(id)sender
{
    TiThreadPerformOnMainThread(^{
        if (sender == _headerViewProxy) {
            UIView* headerView = [[self tableView] tableHeaderView];
            [headerView setFrame:[headerView bounds]];
            [[self tableView] setTableHeaderView:headerView];
            [((TiUIListViewProxy*)[self proxy]) contentsWillChange];
        } else if (sender == _footerViewProxy) {
            UIView *footerView = [[self tableView] tableFooterView];
            [footerView setFrame:[footerView bounds]];
            [[self tableView] setTableFooterView:footerView];
            [((TiUIListViewProxy*)[self proxy]) contentsWillChange];
        } else if (sender == _pullViewProxy) {
            pullThreshhold = ([_pullViewProxy view].frame.origin.y - _pullViewWrapper.bounds.size.height);
        }
    },NO);
}

-(void)setContentOffset_:(id)value withObject:(id)args
{
    CGPoint offset = [TiUtils pointValue:value];
    BOOL animated = [TiUtils boolValue: [args valueForKey:@"animated"] def:NO];
    [_tableView setContentOffset:offset animated:animated];
}

-(void)setContentInsets_:(id)value withObject:(id)props
{
    UIEdgeInsets insets = [TiUtils contentInsets:value];
    BOOL animated = [TiUtils boolValue:@"animated" properties:props def:NO];
    void (^setInset)(void) = ^{
        [_tableView setContentInset:insets];
    };
    if (animated) {
        double duration = [TiUtils doubleValue:@"duration" properties:props def:300]/1000;
        [UIView animateWithDuration:duration animations:setInset];
    }
    else {
        setInset();
    }
}

- (void)setDictTemplates_:(id)args
{
	ENSURE_TYPE_OR_NIL(args,NSDictionary);
	[[self proxy] replaceValue:args forKey:@"dictTemplates" notification:NO];
	[_templates release];
	_templates = [args copy];
    RELEASE_TO_NIL(_measureProxies);
    _measureProxies = [[NSMutableDictionary alloc] init];
    NSEnumerator *enumerator = [_templates keyEnumerator];
    id key;
    while ((key = [enumerator nextObject])) {
        id template = [_templates objectForKey:key];
        if (template != nil) {
            TiUIListItemProxy *theProxy = [[TiUIListItemProxy alloc] initWithListViewProxy:self.listViewProxy inContext:self.listViewProxy.pageContext];
            TiUIListItem* cell = [[TiUIListItem alloc] initWithProxy:theProxy reuseIdentifier:@"__measurementCell__"];
            [theProxy unarchiveFromTemplate:template];
            [_measureProxies setObject:cell forKey:key];
            [theProxy setIndexPath:[NSIndexPath indexPathForRow:-1 inSection:-1]];
            [cell release];
            [theProxy release];
        }
    }
	if (_tableView != nil) {
		[_tableView reloadData];
	}
}

-(TiUIView*)sectionView:(NSInteger)section forLocation:(NSString*)location section:(TiUIListSectionProxy**)sectionResult
{
    TiUIListSectionProxy *proxy = [self.listViewProxy sectionForIndex:section];
    //In the event that proxy is nil, this all flows out to returning nil safely anyways.
    if (sectionResult!=nil) {
        *sectionResult = proxy;
    }
    TiViewProxy* viewproxy = [proxy valueForKey:location];
    if (viewproxy!=nil && [viewproxy isKindOfClass:[TiViewProxy class]]) {
        LayoutConstraint *viewLayout = [viewproxy layoutProperties];
        //If height is not dip, explicitly set it to SIZE
        if (viewLayout->height.type != TiDimensionTypeDip) {
            viewLayout->height = TiDimensionAutoSize;
        }
        
        TiUIView* theView = [viewproxy view];
        if (![viewproxy viewAttached]) {
            [viewproxy windowWillOpen];
            [viewproxy willShow];
            [viewproxy windowDidOpen];
        }
        return theView;
    }
    return nil;
}

#pragma mark - Helper Methods

-(CGFloat)computeRowWidth:(UITableView*)tableView
{
    if (tableView == nil) {
        return 0;
    }
    CGFloat rowWidth = tableView.bounds.size.width;
    
    // Apple does not provide a good way to get information about the index sidebar size
    // in the event that it exists - it silently resizes row content which is "flexible width"
    // but this is not useful for us. This is a problem when we have Ti.UI.SIZE/FILL behavior
    // on row contents, which rely on the height of the row to be accurately precomputed.
    //
    // The following is unreliable since it uses a private API name, but one which has existed
    // since iOS 3.0. The alternative is to grab a specific subview of the tableview itself,
    // which is more fragile.
    if ((sectionTitles == nil) || (tableView != _tableView) ) {
        return rowWidth;
    }
    NSArray* subviews = [tableView subviews];
    if ([subviews count] > 0) {
        // Obfuscate private class name
        Class indexview = NSClassFromString([@"UITableView" stringByAppendingString:@"Index"]);
        for (UIView* view in subviews) {
            if ([view isKindOfClass:indexview]) {
                rowWidth -= [view frame].size.width;
            }
        }
    }
    
    return floorf(rowWidth);
}

-(id)valueWithKey:(NSString*)key atIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary *item = [[self.listViewProxy sectionForIndex:indexPath.section] itemAtIndex:indexPath.row];
    id propertiesValue = [item objectForKey:@"properties"];
    NSDictionary *properties = ([propertiesValue isKindOfClass:[NSDictionary class]]) ? propertiesValue : nil;
    id theValue = [properties objectForKey:key];
    if (theValue == nil) {
        id templateId = [item objectForKey:@"template"];
        if (templateId == nil) {
            templateId = _defaultItemTemplate;
        }
        if (![templateId isKindOfClass:[NSNumber class]]) {
            TiViewTemplate *template = [_templates objectForKey:templateId];
            theValue = [template.properties objectForKey:key];
        }
    }
    
    return theValue;
}

-(void)buildResultsForSearchText
{
    searchActive = ([self.searchString length] > 0);
    RELEASE_TO_NIL(filteredIndices);
    RELEASE_TO_NIL(filteredTitles);
    if (searchActive) {
        BOOL hasResults = NO;
        //Initialize
        if(_searchResults == nil) {
            _searchResults = [[NSMutableArray alloc] init];
        }
        //Clear Out
        [_searchResults removeAllObjects];
        
        //Search Options
        NSStringCompareOptions searchOpts = (caseInsensitiveSearch ? NSCaseInsensitiveSearch : 0);
        
        NSUInteger maxSection = [[self.listViewProxy sectionCount] unsignedIntegerValue];
        NSMutableArray* singleSection = keepSectionsInSearch ? nil : [[NSMutableArray alloc] init];
        for (int i = 0; i < maxSection; i++) {
            NSMutableArray* thisSection = keepSectionsInSearch ? [[NSMutableArray alloc] init] : nil;
            NSUInteger maxItems = [[self.listViewProxy sectionForIndex:i] itemCount];
            for (int j = 0; j < maxItems; j++) {
                NSIndexPath* thePath = [NSIndexPath indexPathForRow:j inSection:i];
                id theValue = [self valueWithKey:@"searchableText" atIndexPath:thePath];
                if (theValue!=nil && [[TiUtils stringValue:theValue] rangeOfString:self.searchString options:searchOpts].location != NSNotFound) {
                    (thisSection != nil) ? [thisSection addObject:thePath] : [singleSection addObject:thePath];
                    hasResults = YES;
                }
            }
            if (thisSection != nil) {
                if ([thisSection count] > 0) {
                    [_searchResults addObject:thisSection];
                    
                    if (sectionTitles != nil && sectionIndices != nil) {
                        NSNumber* theIndex = [NSNumber numberWithInt:i];
                        if ([sectionIndices containsObject:theIndex]) {
                            id theTitle = [sectionTitles objectAtIndex:[sectionIndices indexOfObject:theIndex]];
                            if (filteredTitles == nil) {
                                filteredTitles = [[NSMutableArray alloc] init];
                            }
                            if (filteredIndices == nil) {
                                filteredIndices = [[NSMutableArray alloc] init];
                            }
                            [filteredTitles addObject:theTitle];
                            [filteredIndices addObject:NUMUINTEGER([_searchResults count] -1)];
                        }
                    }
                }
                [thisSection release];
            }
        }
        if (singleSection != nil) {
            if ([singleSection count] > 0) {
                [_searchResults addObject:singleSection];
            }
            [singleSection release];
        }
        if (!hasResults) {
            if ([(TiViewProxy*)self.proxy _hasListeners:@"noresults" checkParent:NO]) {
                [self.proxy fireEvent:@"noresults" withObject:nil propagate:NO reportSuccess:NO errorCode:0 message:nil];
            }
        }
        
    } else {
        RELEASE_TO_NIL(_searchResults);
    }
}

-(BOOL) isSearchActive
{
    return searchActive || [searchController isActive];
}

- (void)updateSearchResults:(id)unused
{
    if (searchActive) {
        [self buildResultsForSearchText];
    }
    [_tableView reloadData];
    if ([searchController isActive]) {
        [[searchController searchResultsTableView] reloadData];
    } 
}

-(NSIndexPath*)pathForSearchPath:(NSIndexPath*)indexPath
{
    if (_searchResults != nil && [_searchResults count] > indexPath.section) {
        NSArray* sectionResults = [_searchResults objectAtIndex:indexPath.section];
        if([sectionResults count] > indexPath.row) {
            return [sectionResults objectAtIndex:indexPath.row];
        }
    }
    return indexPath;
}

-(NSInteger)sectionForSearchSection:(NSInteger)section
{
    if (_searchResults != nil) {
        NSArray* sectionResults = [_searchResults objectAtIndex:section];
        NSIndexPath* thePath = [sectionResults objectAtIndex:0];
        return thePath.section;
    }
    return section;
}

#pragma mark - Public API

-(void)setSeparatorInsets_:(id)arg
{
    [self tableView];
    if ([arg isKindOfClass:[NSDictionary class]]) {
        CGFloat left = [TiUtils floatValue:@"left" properties:arg def:_defaultSeparatorInsets.left];
        CGFloat right = [TiUtils floatValue:@"right" properties:arg def:_defaultSeparatorInsets.right];
        [_tableView setSeparatorInset:UIEdgeInsetsMake(0, left, 0, right)];
    } else {
        [_tableView setSeparatorInset:_defaultSeparatorInsets];
    }
    if (![searchController isActive]) {
        [_tableView setNeedsDisplay];
    }
}

-(void)setPruneSectionsOnEdit_:(id)args
{
    pruneSections = [TiUtils boolValue:args def:NO];
}

-(void)setCanScroll_:(id)args
{
    UITableView *table = [self tableView];
    [table setScrollEnabled:[TiUtils boolValue:args def:YES]];
}

-(void)setSeparatorStyle_:(id)arg
{
    [[self tableView] setSeparatorStyle:[TiUtils intValue:arg]];
}

-(void)setSeparatorColor_:(id)arg
{
    TiColor *color = [TiUtils colorValue:arg];
    [[self tableView] setSeparatorColor:[color _color]];
}

- (void)setDefaultItemTemplate_:(id)args
{
	if (![args isKindOfClass:[NSString class]] && ![args isKindOfClass:[NSNumber class]]) {
		ENSURE_TYPE_OR_NIL(args,NSString);
	}
	[_defaultItemTemplate release];
	_defaultItemTemplate = [args copy];
	if (_tableView != nil) {
		[_tableView reloadData];
	}	
}

- (void)setRowHeight_:(id)height
{
	_rowHeight = [TiUtils dimensionValue:height];
	if (TiDimensionIsDip(_rowHeight)) {
		[_tableView setRowHeight:_rowHeight.value];
	}
}

- (void)setBackgroundColor_:(id)arg
{
	if (_tableView != nil) {
		[[self class] setBackgroundColor:[TiUtils colorValue:arg] onTable:_tableView];
	}
}

- (void)setHeaderTitle_:(id)args
{
    [_headerWrapper removeAllChildren:nil];
    TiViewProxy *theProxy = [[self class] titleViewForText:[TiUtils stringValue:args] inTable:[self tableView] footer:NO];
    [_headerWrapper add:theProxy];
}

- (void)setFooterTitle_:(id)args
{
    if (IS_NULL_OR_NIL(args)) {
        [_footerViewProxy setProxyObserver:nil];
        [_footerViewProxy windowWillClose];
        [self.tableView setTableFooterView:nil];
        [_footerViewProxy windowDidClose];
        RELEASE_TO_NIL(_footerViewProxy);
        [((TiUIListViewProxy*)[self proxy]) contentsWillChange];
    } else {
        [self configureFooter];
        [_footerViewProxy removeAllChildren:nil];
        TiViewProxy *theProxy = [[self class] titleViewForText:[TiUtils stringValue:args] inTable:[self tableView] footer:YES];
        [_footerViewProxy add:theProxy];
    }
}

-(void)setHeaderView_:(id)args
{
    ENSURE_SINGLE_ARG_OR_NIL(args,TiViewProxy);
    [self tableView];
    [_headerWrapper removeAllChildren:nil];
    if (args!=nil) {
        [_headerWrapper add:(TiViewProxy*) args];
    }
}

-(void)setFooterView_:(id)args
{
    ENSURE_SINGLE_ARG_OR_NIL(args,TiViewProxy);
    if (IS_NULL_OR_NIL(args)) {
        [_footerViewProxy setProxyObserver:nil];
        [_footerViewProxy windowWillClose];
        [self.tableView setTableFooterView:nil];
        [_footerViewProxy windowDidClose];
        RELEASE_TO_NIL(_footerViewProxy);
        [((TiUIListViewProxy*)[self proxy]) contentsWillChange];
    } else {
        [self configureFooter];
        [_footerViewProxy removeAllChildren:nil];
        [_footerViewProxy add:(TiViewProxy*) args];
    }
}

-(void)setRefreshControl_:(id)args
{
#ifdef USE_TI_UIREFRESHCONTROL
    ENSURE_SINGLE_ARG_OR_NIL(args,TiUIRefreshControlProxy);
    [[_refreshControlProxy control] removeFromSuperview];
    RELEASE_TO_NIL(_refreshControlProxy);
    [[self proxy] replaceValue:args forKey:@"refreshControl" notification:NO];
    if (args != nil) {
        _refreshControlProxy = [args retain];
        [[self tableView] addSubview:[_refreshControlProxy control]];
    }
#endif
}

-(void)setPullView_:(id)args
{
    ENSURE_SINGLE_ARG_OR_NIL(args,TiViewProxy);
    if (args == nil) {
        [_pullViewProxy setProxyObserver:nil];
        [_pullViewProxy windowWillClose];
        [_pullViewWrapper removeFromSuperview];
        [_pullViewProxy windowDidClose];
        RELEASE_TO_NIL(_pullViewWrapper);
        RELEASE_TO_NIL(_pullViewProxy);
    } else {
        if ([self tableView].bounds.size.width==0)
        {
            [self performSelector:@selector(setPullView_:) withObject:args afterDelay:0.1];
            return;
        }
        if (_pullViewProxy != nil) {
            [_pullViewProxy setProxyObserver:nil];
            [_pullViewProxy windowWillClose];
            [_pullViewProxy windowDidClose];
            RELEASE_TO_NIL(_pullViewProxy);
        }
        if (_pullViewWrapper == nil) {
            _pullViewWrapper = [[UIView alloc] init];
            [_tableView addSubview:_pullViewWrapper];
        }
        CGSize refSize = _tableView.bounds.size;
        [_pullViewWrapper setFrame:CGRectMake(0.0, 0.0 - refSize.height, refSize.width, refSize.height)];
        _pullViewProxy = [args retain];
        TiColor* pullBgColor = [TiUtils colorValue:[_pullViewProxy valueForUndefinedKey:@"pullBackgroundColor"]];
        _pullViewWrapper.backgroundColor = ((pullBgColor == nil) ? [UIColor lightGrayColor] : [pullBgColor color]);
        LayoutConstraint *viewLayout = [_pullViewProxy layoutProperties];
        //If height is not dip, explicitly set it to SIZE
        if (viewLayout->height.type != TiDimensionTypeDip) {
            viewLayout->height = TiDimensionAutoSize;
        }
        //If bottom is not dip set it to 0
        if (viewLayout->bottom.type != TiDimensionTypeDip) {
            viewLayout->bottom = TiDimensionZero;
        }
        //Remove other vertical positioning constraints
        viewLayout->top = TiDimensionUndefined;
        viewLayout->centerY = TiDimensionUndefined;
        
        [_pullViewProxy setProxyObserver:self];
        [_pullViewProxy windowWillOpen];
        [_pullViewWrapper addSubview:[_pullViewProxy view]];
        _pullViewProxy.parentVisible = YES;
        [_pullViewProxy refreshSize];
        [_pullViewProxy willChangeSize];
        [_pullViewProxy windowDidOpen];
    }
    
}

-(void)setKeepSectionsInSearch_:(id)args
{
    if (searchViewProxy == nil) {
        keepSectionsInSearch = [TiUtils boolValue:args def:NO];
        if (searchActive) {
            [self buildResultsForSearchText];
            [_tableView reloadData];
        }
    } else {
        keepSectionsInSearch = NO;
    }
}

- (void)setScrollIndicatorStyle_:(id)value
{
	[self.tableView setIndicatorStyle:[TiUtils intValue:value def:UIScrollViewIndicatorStyleDefault]];
}

- (void)setWillScrollOnStatusTap_:(id)value
{
	[self.tableView setScrollsToTop:[TiUtils boolValue:value def:YES]];
}

- (void)setShowVerticalScrollIndicator_:(id)value
{
	[self.tableView setShowsVerticalScrollIndicator:[TiUtils boolValue:value]];
}

-(void)setAllowsSelection_:(id)value
{
    [[self tableView] setAllowsSelection:[TiUtils boolValue:value]];
}

-(void)setEditing_:(id)args
{
    if ([TiUtils boolValue:args def:NO] != editing) {
        editing = !editing;
        [[self tableView] beginUpdates];
        [_tableView setEditing:editing animated:YES];
        [_tableView endUpdates];
    }
}

#pragma mark - Search Support
-(void)setCaseInsensitiveSearch_:(id)args
{
    caseInsensitiveSearch = [TiUtils boolValue:args def:YES];
    if (searchActive) {
        [self buildResultsForSearchText];
        if ([searchController isActive]) {
            [[searchController searchResultsTableView] reloadData];
        } else {
            [_tableView reloadData];
        }
    }
}

-(void)setSearchText_:(id)args
{
    id searchView = [self.proxy valueForKey:@"searchView"];
    if (!IS_NULL_OR_NIL(searchView)) {
        DebugLog(@"Can not use searchText with searchView. Ignoring call.");
        return;
    }
    self.searchString = [TiUtils stringValue:args];
    [self buildResultsForSearchText];
    [_tableView reloadData];
}

-(void)setSearchView_:(id)args
{
    ENSURE_TYPE_OR_NIL(args,TiUISearchBarProxy);
    [self tableView];
    [searchViewProxy setDelegate:nil];
    RELEASE_TO_NIL(searchViewProxy);
    RELEASE_TO_NIL(tableController);
    RELEASE_TO_NIL(searchController);
    [_searchWrapper removeAllChildren:nil];

    if (args != nil) {
        searchViewProxy = [args retain];
        [searchViewProxy setDelegate:self];
        [_searchWrapper add:searchViewProxy];
        NSString *curPlaceHolder = [[searchViewProxy searchBar] placeholder];
        if (curPlaceHolder == nil) {
            [[searchViewProxy searchBar] setPlaceholder:@"Search"];
        }
        
        keepSectionsInSearch = NO;
    } else {
        keepSectionsInSearch = [TiUtils boolValue:[self.proxy valueForKey:@"keepSectionsInSearch"] def:NO];
    }
    
}

-(void)cleanup:(id)unused
{
    if (_headerViewProxy != nil) {
        [_headerViewProxy windowWillClose];
    }
    
    if (_footerViewProxy != nil) {
        [_footerViewProxy windowWillClose];
    }
}

#pragma mark - SectionIndexTitle Support

-(void)setSectionIndexTitles_:(id)args
{
    ENSURE_TYPE_OR_NIL(args, NSArray);
    
    RELEASE_TO_NIL(sectionTitles);
    RELEASE_TO_NIL(sectionIndices);
    RELEASE_TO_NIL(filteredTitles);
    RELEASE_TO_NIL(filteredIndices);
    
    NSArray* theIndex = args;
	if ([theIndex count] > 0) {
        sectionTitles = [[NSMutableArray alloc] initWithCapacity:[theIndex count]];
        sectionIndices = [[NSMutableArray alloc] initWithCapacity:[theIndex count]];
        
        for (NSDictionary *entry in theIndex) {
            ENSURE_DICT(entry);
            NSString *title = [entry objectForKey:@"title"];
            id index = [entry objectForKey:@"index"];
            [sectionTitles addObject:title];
            [sectionIndices addObject:[NSNumber numberWithInt:[TiUtils intValue:index]]];
        }
    }
    if (searchViewProxy == nil) {
        if (searchActive) {
            [self buildResultsForSearchText];
        }
    }
    [_tableView reloadSectionIndexTitles];
}

#pragma mark - SectionIndexTitle Support Datasource methods.

-(NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if (tableView != _tableView) {
        return nil;
    }
    
    if (editing) {
        return nil;
    }
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            return filteredTitles;
        } else {
            return nil;
        }
    }
    
    return sectionTitles;
}

-(NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)theIndex
{
    if (tableView != _tableView) {
        return 0;
    }
    
    if (editing) {
        return 0;
    }
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) && (filteredTitles != nil) && (filteredIndices != nil) ) {
            // get the index for the title
            NSUInteger index = [filteredTitles indexOfObject:title];

            if([(TiViewProxy*)[self proxy] _hasListeners:@"indexclick" checkParent:NO]) {
                NSDictionary *eventArgs = [NSDictionary dictionaryWithObjectsAndKeys: title, @"title", NUMUINTEGER(index), @"index", nil];
                [[self proxy] fireEvent:@"indexclick" withObject:eventArgs propagate:NO];
            }

            if (index > 0 && (index < [filteredIndices count]) ) {
                return [[filteredIndices objectAtIndex:index] intValue];
            }
            return 0;
        } else {
            return 0;
        }
    }
    
    if ( (sectionTitles != nil) && (sectionIndices != nil) ) {
        // get the index for the title
        NSUInteger index = [sectionTitles indexOfObject:title];
        int sectionIndex = [[sectionIndices objectAtIndex:index] intValue];

        if([(TiViewProxy*)[self proxy] _hasListeners:@"indexclick" checkParent:NO]) {
            NSDictionary *eventArgs = [NSDictionary dictionaryWithObjectsAndKeys: title, @"title", NUMUINTEGER(index), @"index", nil];
            [[self proxy] fireEvent:@"indexclick" withObject:eventArgs propagate:NO];
        }

        if (index > 0 && (index < [sectionIndices count]) ) {
            return sectionIndex;
        }
        return 0;
    }
    return 0;
}

#pragma mark - Editing Support

-(BOOL)canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    id editValue = [self valueWithKey:@"canEdit" atIndexPath:indexPath];
    //canEdit if undefined is false
    return [TiUtils boolValue:editValue def:NO];
}


-(BOOL)canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    id moveValue = [self valueWithKey:@"canMove" atIndexPath:indexPath];
    //canMove if undefined is false
    return [TiUtils boolValue:moveValue def:NO];
}

-(NSArray*)editActionsFromValue:(id)value
{
    ENSURE_ARRAY(value);
    NSArray* propArray = (NSArray*)value;
    NSMutableArray* returnArray = nil;
    
    for (id prop in propArray) {
        ENSURE_DICT(prop);
        NSString* title = [TiUtils stringValue:@"title" properties:prop];
        int actionStyle = [TiUtils intValue:@"style" properties:prop];
        TiColor* theColor = [TiUtils colorValue:@"color" properties:prop];
    
        UITableViewRowAction* theAction = [UITableViewRowAction rowActionWithStyle:actionStyle title:title handler:^(UITableViewRowAction *action, NSIndexPath *indexPath){
            NSString* eventName = @"editaction";
            
            if ([self.listViewProxy _hasListeners:eventName checkParent:NO]) {
                TiUIListSectionProxy* theSection = [[self.listViewProxy sectionForIndex:indexPath.section] retain];
                NSDictionary *theItem = [[theSection itemAtIndex:indexPath.row] retain];
                NSMutableDictionary *eventObject = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                    theSection, @"section",
                                                    NUMINTEGER(indexPath.section), @"sectionIndex",
                                                    NUMINTEGER(indexPath.row), @"itemIndex",
                                                    action.title,@"action",
                                                    nil];
                id propertiesValue = [theItem objectForKey:@"properties"];
                NSDictionary *properties = ([propertiesValue isKindOfClass:[NSDictionary class]]) ? propertiesValue : nil;
                id itemId = [properties objectForKey:@"itemId"];
                if (itemId != nil) {
                    [eventObject setObject:itemId forKey:@"itemId"];
                }
                [self.proxy fireEvent:eventName withObject:eventObject withSource:self.proxy propagate:NO reportSuccess:NO errorCode:0 message:nil];
                [eventObject release];
                [theItem release];
                [theSection release];
            }
            
            // Hide editActions after selection
            [[self tableView] setEditing:NO];

        }];
        if (theColor != nil) {
            theAction.backgroundColor = [theColor color];
        }
        if (returnArray == nil) {
            returnArray = [NSMutableArray arrayWithObject:theAction];
        } else {
            [returnArray addObject:theAction];
        }
    }
    
    return returnArray;
}

#pragma mark - Editing Support Datasource methods.

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != _tableView) {
        return NO;
    }
    
    if (searchActive) {
        return NO;
    }
    
    if ([self canEditRowAtIndexPath:indexPath]) {
        return YES;
    }
    if (editing) {
        return [self canMoveRowAtIndexPath:indexPath];
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        TiUIListSectionProxy* theSection = [[self.listViewProxy sectionForIndex:indexPath.section] retain];
        NSDictionary *theItem = [[theSection itemAtIndex:indexPath.row] retain];
        
        //Delete Data
        [theSection deleteItemAtIndex:indexPath.row];
        
        //Fire the delete Event if required
        NSString *eventName = @"delete";
        if ([self.proxy _hasListeners:eventName]) {
        
            NSMutableDictionary *eventObject = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                theSection, @"section",
                                                NUMINTEGER(indexPath.section), @"sectionIndex",
                                                NUMINTEGER(indexPath.row), @"itemIndex",
                                                nil];
            id propertiesValue = [theItem objectForKey:@"properties"];
            NSDictionary *properties = ([propertiesValue isKindOfClass:[NSDictionary class]]) ? propertiesValue : nil;
            id itemId = [properties objectForKey:@"itemId"];
            if (itemId != nil) {
                [eventObject setObject:itemId forKey:@"itemId"];
            }
            [self.proxy fireEvent:eventName withObject:eventObject withSource:self.proxy propagate:NO reportSuccess:NO errorCode:0 message:nil];
            [eventObject release];
        }
        [theItem release];
        
        BOOL emptySection = NO;
        
        if ([theSection itemCount] == 0) {
            emptySection = YES;
            if (pruneSections) {
                [self.listViewProxy deleteSectionAtIndex:indexPath.section];
            }
        }
        
        BOOL emptyTable = NO;
        NSUInteger sectionCount = [[self.listViewProxy sectionCount] unsignedIntValue];
        if ( sectionCount == 0) {
            emptyTable = YES;
        }
        
        //Reload the data now.
        [tableView beginUpdates];
        if (emptyTable) {
            //Table is empty. Just reload fake section with FADE animation to clear out header and footers
            NSIndexSet *theSet = [NSIndexSet indexSetWithIndex:0];
            [tableView reloadSections:theSet withRowAnimation:UITableViewRowAnimationFade];
        } else if (emptySection) {
            //Section is empty.
            if (pruneSections) {
                //Delete the section
                
                BOOL needsReload = (indexPath.section < sectionCount);
                //If this is not the last section we need to set indices for all the sections coming in after this that are visible.
                //Otherwise the events will not work properly since the indexPath stored in the cell will be incorrect.
                
                if (needsReload) {
                    NSArray* visibleRows = [tableView indexPathsForVisibleRows];
                    [visibleRows enumerateObjectsUsingBlock:^(NSIndexPath *vIndexPath, NSUInteger idx, BOOL *stop) {
                        if (vIndexPath.section > indexPath.section) {
                            //This belongs to the next section. So set the right indexPath otherwise events wont work properly.
                            NSIndexPath *newIndex = [NSIndexPath indexPathForRow:vIndexPath.row inSection:(vIndexPath.section -1)];
                            UITableViewCell* theCell = [tableView cellForRowAtIndexPath:vIndexPath];
                            if ([theCell isKindOfClass:[TiUIListItem class]]) {
                                ((TiUIListItem*)theCell).proxy.indexPath = newIndex;
                            }
                        }
                    }];
                }
                NSIndexSet *deleteSet = [NSIndexSet indexSetWithIndex:indexPath.section];
                [tableView deleteSections:deleteSet withRowAnimation:UITableViewRowAnimationFade];
            } else {
                //Just delete the row. Section stays
                [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            }
        } else {
            //Just delete the row.
            BOOL needsReload = (indexPath.row < [theSection itemCount]);
            //If this is not the last row need to set indices for all rows in the section following this row.
            //Otherwise the events will not work properly since the indexPath stored in the cell will be incorrect.
            
            if (needsReload) {
                NSArray* visibleRows = [tableView indexPathsForVisibleRows];
                [visibleRows enumerateObjectsUsingBlock:^(NSIndexPath *vIndexPath, NSUInteger idx, BOOL *stop) {
                    if ( (vIndexPath.section == indexPath.section) && (vIndexPath.row > indexPath.row) ) {
                        //This belongs to the same section. So set the right indexPath otherwise events wont work properly.
                        NSIndexPath *newIndex = [NSIndexPath indexPathForRow:(vIndexPath.row - 1) inSection:(vIndexPath.section)];
                        UITableViewCell* theCell = [tableView cellForRowAtIndexPath:vIndexPath];
                        if ([theCell isKindOfClass:[TiUIListItem class]]) {
                            ((TiUIListItem*)theCell).proxy.indexPath = newIndex;
                        }
                    }
                }];
            }
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        
        }
        [tableView endUpdates];
        [theSection release];
    }
}

#pragma mark - Editing Support Delegate Methods.

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    //No support for insert style yet
    if ([self canEditRowAtIndexPath:indexPath]) {
        return UITableViewCellEditingStyleDelete;
    } else {
        return UITableViewCellEditingStyleNone;
    }
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != _tableView) {
        return nil;
    }
    
    if (searchActive) {
        return nil;
    }
    
    if (![self canEditRowAtIndexPath:indexPath]) {
        return nil;
    }
    
    id editValue = [self valueWithKey:@"editActions" atIndexPath:indexPath];
    
    if (IS_NULL_OR_NIL(editValue)) {
        return nil;
    }
    
    return [self editActionsFromValue:editValue];

}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self canEditRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    editing = YES;
    [self.proxy replaceValue:NUMBOOL(editing) forKey:@"editing" notification:NO];
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    editing = [_tableView isEditing];
    [self.proxy replaceValue:NUMBOOL(editing) forKey:@"editing" notification:NO];
    if (!editing) {
        [_tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
    }
}

#pragma mark - UITableViewDataSource

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != _tableView) {
        return NO;
    }
    
    if (searchActive) {
        return NO;
    }
    
	return [self canMoveRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
    NSInteger fromSectionIndex = [fromIndexPath section];
    NSInteger fromRowIndex = [fromIndexPath row];
    NSInteger toSectionIndex = [toIndexPath section];
    NSInteger toRowIndex = [toIndexPath row];
    
    
    
    if (fromSectionIndex == toSectionIndex) {
        if (fromRowIndex == toRowIndex) {
            return;
        }
        //Moving a row in the same index. Just move and reload section
        TiUIListSectionProxy* theSection = [[self.listViewProxy sectionForIndex:fromSectionIndex] retain];
        NSDictionary *theItem = [[theSection itemAtIndex:fromRowIndex] retain];
        
        //Delete Data
        [theSection deleteItemAtIndex:fromRowIndex];
        
        //Insert the data
        [theSection addItem:theItem atIndex:toRowIndex];
        
        //Fire the move Event if required
        NSString *eventName = @"move";
        if ([self.proxy _hasListeners:eventName]) {
            
            NSMutableDictionary *eventObject = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                theSection, @"section",
                                                NUMINTEGER(fromSectionIndex), @"sectionIndex",
                                                NUMINTEGER(fromRowIndex), @"itemIndex",
                                                theSection,@"targetSection",
                                                NUMINTEGER(toSectionIndex), @"targetSectionIndex",
                                                NUMINTEGER(toRowIndex), @"targetItemIndex",
                                                nil];
            id propertiesValue = [theItem objectForKey:@"properties"];
            NSDictionary *properties = ([propertiesValue isKindOfClass:[NSDictionary class]]) ? propertiesValue : nil;
            id itemId = [properties objectForKey:@"itemId"];
            if (itemId != nil) {
                [eventObject setObject:itemId forKey:@"itemId"];
            }
            [self.proxy fireEvent:eventName withObject:eventObject withSource:self.proxy propagate:NO reportSuccess:NO errorCode:0 message:nil];
            [eventObject release];
        }
        
        [tableView reloadData];
        
        [theSection release];
        [theItem release];
        
        
    } else {
        TiUIListSectionProxy* fromSection = [[self.listViewProxy sectionForIndex:fromSectionIndex] retain];
        NSDictionary *theItem = [[fromSection itemAtIndex:fromRowIndex] retain];
        TiUIListSectionProxy* toSection = [[self.listViewProxy sectionForIndex:toSectionIndex] retain];
        
        //Delete Data
        [fromSection deleteItemAtIndex:fromRowIndex];
        
        //Insert the data
        [toSection addItem:theItem atIndex:toRowIndex];
        
        //Fire the move Event if required
        NSString *eventName = @"move";
        if ([self.proxy _hasListeners:eventName]) {
            
            NSMutableDictionary *eventObject = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                fromSection, @"section",
                                                NUMINTEGER(fromSectionIndex), @"sectionIndex",
                                                NUMINTEGER(fromRowIndex), @"itemIndex",
                                                toSection,@"targetSection",
                                                NUMINTEGER(toSectionIndex), @"targetSectionIndex",
                                                NUMINTEGER(toRowIndex), @"targetItemIndex",
                                                nil];
            id propertiesValue = [theItem objectForKey:@"properties"];
            NSDictionary *properties = ([propertiesValue isKindOfClass:[NSDictionary class]]) ? propertiesValue : nil;
            id itemId = [properties objectForKey:@"itemId"];
            if (itemId != nil) {
                [eventObject setObject:itemId forKey:@"itemId"];
            }
            [self.proxy fireEvent:eventName withObject:eventObject];
            [eventObject release];
        }
        
        if ([fromSection itemCount] == 0) {
            if (pruneSections) {
                [self.listViewProxy deleteSectionAtIndex:fromSectionIndex];
            }
        }
        
        [tableView reloadData];
        
        [fromSection release];
        [toSection release];
        [theItem release];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    NSUInteger sectionCount = 0;
    
    //TIMOB-15526
    if (tableView != _tableView && tableView.backgroundColor == [UIColor clearColor]) {
        tableView.backgroundColor = [UIColor whiteColor];
    }

    if (_searchResults != nil) {
        sectionCount = [_searchResults count];
    } else {
        sectionCount = [self.listViewProxy.sectionCount unsignedIntegerValue];
    }
    return MAX(0,sectionCount);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_searchResults != nil) {
        if ([_searchResults count] <= section) {
            return 0;
        }
        NSArray* theSection = [_searchResults objectAtIndex:section];
        return [theSection count];
        
    } else {
        TiUIListSectionProxy* theSection = [self.listViewProxy sectionForIndex:section];
        if (theSection != nil) {
            return theSection.itemCount;
        }
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath* realIndexPath = [self pathForSearchPath:indexPath];
    TiUIListSectionProxy* theSection = [self.listViewProxy sectionForIndex:realIndexPath.section];
    NSInteger maxItem = 0;
    
    if (_searchResults != nil && [_searchResults count] > indexPath.section) {
        NSArray* sectionResults = [_searchResults objectAtIndex:indexPath.section];
        maxItem = [sectionResults count];
    } else {
        maxItem = theSection.itemCount;
    }
    
    NSDictionary *item = [theSection itemAtIndex:realIndexPath.row];
    id templateId = [item objectForKey:@"template"];
    if (templateId == nil) {
        templateId = _defaultItemTemplate;
    }
    NSString *cellIdentifier = [templateId isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"TiUIListView__internal%@", templateId]: [templateId description];
    TiUIListItem *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        id<TiEvaluator> context = self.listViewProxy.executionContext;
        if (context == nil) {
            context = self.listViewProxy.pageContext;
        }
        TiUIListItemProxy *cellProxy = [[TiUIListItemProxy alloc] initWithListViewProxy:self.listViewProxy inContext:context];
        if ([templateId isKindOfClass:[NSNumber class]]) {
            UITableViewCellStyle cellStyle = [templateId unsignedIntegerValue];
            cell = [[TiUIListItem alloc] initWithStyle:cellStyle reuseIdentifier:cellIdentifier proxy:cellProxy];
        } else {
            cell = [[TiUIListItem alloc] initWithProxy:cellProxy reuseIdentifier:cellIdentifier];
            id template = [_templates objectForKey:templateId];
            if (template != nil) {
                [cellProxy unarchiveFromTemplate:template];
            }
        }
        
        if ([TiUtils isIOS8OrGreater] && (tableView == _tableView)) {
            [cell setLayoutMargins:UIEdgeInsetsZero];
        }
        
        [cellProxy release];
        [cell autorelease];
    }

    if (tableView.style == UITableViewStyleGrouped) {
        if (indexPath.row == 0) {
            if (maxItem == 1) {
                [cell setPosition:TiCellBackgroundViewPositionSingleLine isGrouped:YES];
            } else {
                [cell setPosition:TiCellBackgroundViewPositionTop isGrouped:YES];
            }
        } else if (indexPath.row == (maxItem - 1) ) {
            [cell setPosition:TiCellBackgroundViewPositionBottom isGrouped:YES];
        } else {
            [cell setPosition:TiCellBackgroundViewPositionMiddle isGrouped:YES];
        }
    } else {
        [cell setPosition:TiCellBackgroundViewPositionMiddle isGrouped:NO];
    }

    cell.dataItem = item;
    cell.proxy.indexPath = realIndexPath;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (tableView != _tableView) {
        return nil;
    }
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            NSInteger realSection = [self sectionForSearchSection:section];
            return [[self.listViewProxy sectionForIndex:realSection] headerTitle];
        } else {
            return nil;
        }
    }
    
    return [[self.listViewProxy sectionForIndex:section] headerTitle];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (tableView != _tableView) {
        return nil;
    }
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            NSInteger realSection = [self sectionForSearchSection:section];
            return [[self.listViewProxy sectionForIndex:realSection] footerTitle];
        } else {
            return nil;
        }
    }
    return [[self.listViewProxy sectionForIndex:section] footerTitle];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    //Let the cell configure its background
    [(TiUIListItem*)cell configureCellBackground];
    
    NSIndexPath* realPath = [self pathForSearchPath:indexPath];
    id tintValue = [self valueWithKey:@"tintColor" atIndexPath:realPath];
    UIColor* theTint = [[TiUtils colorValue:tintValue] color];
    if (theTint == nil) {
        theTint = [tableView tintColor];
    }
    [cell setTintColor:theTint];
    
    if (searchActive || (tableView != _tableView)) {
        return;
    } else {
        //Tell the proxy about the cell to be displayed for marker event
        [self.listViewProxy willDisplayCell:indexPath];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (tableView != _tableView) {
        return nil;
    }
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            NSInteger realSection = [self sectionForSearchSection:section];
            return [self sectionView:realSection forLocation:@"headerView" section:nil];
        } else {
            return nil;
        }
    }

    if ( bReverseMode == true)
    {
        if ( tableView != nil && [tableView numberOfSections] > 0 && [tableView numberOfRowsInSection:0] > 0 )
        {
            [tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[tableView numberOfRowsInSection:0]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:false];
        }
        
        if ( isBottom == false )
        {
            isBottom = true;
            [self.listViewProxy setBottomState:NUMBOOL(isBottom)];
        }
    }
    
    return [self sectionView:section forLocation:@"headerView" section:nil];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    if (tableView != _tableView) {
        return nil;
    }
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            NSInteger realSection = [self sectionForSearchSection:section];
            return [self sectionView:realSection forLocation:@"footerView" section:nil];
        } else {
            return nil;
        }
    }
    
    return [self sectionView:section forLocation:@"footerView" section:nil];
}

#define DEFAULT_SECTION_HEADERFOOTER_HEIGHT 20.0

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (tableView != _tableView) {
        return 0.0;
    }
    
    NSInteger realSection = section;
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            realSection = [self sectionForSearchSection:section];
        } else {
            return 0.0;
        }
    }
    
    TiUIListSectionProxy *sectionProxy = [self.listViewProxy sectionForIndex:realSection];
    TiUIView *view = [self sectionView:realSection forLocation:@"headerView" section:nil];
	
    CGFloat size = 0.0;
    if (view!=nil) {
        TiViewProxy* viewProxy = (TiViewProxy*) [view proxy];
        LayoutConstraint *viewLayout = [viewProxy layoutProperties];
        switch (viewLayout->height.type)
        {
            case TiDimensionTypeDip:
                size += viewLayout->height.value;
                break;
            case TiDimensionTypeAuto:
            case TiDimensionTypeAutoSize:
                size += [viewProxy autoHeightForSize:[self.tableView bounds].size];
                break;
            default:
                size+=DEFAULT_SECTION_HEADERFOOTER_HEIGHT;
                break;
        }
    }
    /*
     * This behavior is slightly more complex between iOS 4 and iOS 5 than you might believe, and Apple's
     * documentation is once again misleading. It states that in iOS 4 this value was "ignored if
     * -[delegate tableView:viewForHeaderInSection:] returned nil" but apparently a non-nil value for
     * -[delegate tableView:titleForHeaderInSection:] is considered a valid value for height handling as well,
     * provided it is NOT the empty string.
     *
     * So for parity with iOS 4, iOS 5 must similarly treat the empty string header as a 'nil' value and
     * return a 0.0 height that is overridden by the system.
     */
    else if ([sectionProxy headerTitle]!=nil) {
        if ([[sectionProxy headerTitle] isEqualToString:@""]) {
            return size;
        }
        size+=[tableView sectionHeaderHeight];
        
        if (size < DEFAULT_SECTION_HEADERFOOTER_HEIGHT) {
            size += DEFAULT_SECTION_HEADERFOOTER_HEIGHT;
        }
    }
    return size;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if (tableView != _tableView) {
        return 0.0;
    }
    
    NSInteger realSection = section;
    
    if (searchActive) {
        if (keepSectionsInSearch && ([_searchResults count] > 0) ) {
            realSection = [self sectionForSearchSection:section];
        } else {
            return 0.0;
        }
    }

    TiUIListSectionProxy *sectionProxy = [self.listViewProxy sectionForIndex:realSection];
    TiUIView *view = [self sectionView:realSection forLocation:@"footerView" section:nil];
	
    CGFloat size = 0.0;
    if (view!=nil) {
        TiViewProxy* viewProxy = (TiViewProxy*) [view proxy];
        LayoutConstraint *viewLayout = [viewProxy layoutProperties];
        switch (viewLayout->height.type)
        {
            case TiDimensionTypeDip:
                size += viewLayout->height.value;
                break;
            case TiDimensionTypeAuto:
            case TiDimensionTypeAutoSize:
                size += [viewProxy autoHeightForSize:[self.tableView bounds].size];
                break;
            default:
                size+=DEFAULT_SECTION_HEADERFOOTER_HEIGHT;
                break;
        }
    }
    /*
     * This behavior is slightly more complex between iOS 4 and iOS 5 than you might believe, and Apple's
     * documentation is once again misleading. It states that in iOS 4 this value was "ignored if
     * -[delegate tableView:viewForHeaderInSection:] returned nil" but apparently a non-nil value for
     * -[delegate tableView:titleForHeaderInSection:] is considered a valid value for height handling as well,
     * provided it is NOT the empty string.
     *
     * So for parity with iOS 4, iOS 5 must similarly treat the empty string header as a 'nil' value and
     * return a 0.0 height that is overridden by the system.
     */
    else if ([sectionProxy footerTitle]!=nil) {
        if ([[sectionProxy footerTitle] isEqualToString:@""]) {
            return size;
        }
        size+=[tableView sectionFooterHeight];
        
        if (size < DEFAULT_SECTION_HEADERFOOTER_HEIGHT) {
            size += DEFAULT_SECTION_HEADERFOOTER_HEIGHT;
        }
    }
    return size;
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath* realPath = [self pathForSearchPath:indexPath];
    
    id heightValue = [self valueWithKey:@"height" atIndexPath:realPath];
    
    TiDimension height = _rowHeight;
    if (heightValue != nil) {
        height = [TiUtils dimensionValue:heightValue];
    }
    if (TiDimensionIsDip(height)) {
        return height.value;
    } else if (TiDimensionIsAutoSize(height)) {
        TiUIListSectionProxy* theSection = [self.listViewProxy sectionForIndex:realPath.section];
        NSDictionary *item = [theSection itemAtIndex:realPath.row]; //get the item data
        id templateId = [item objectForKey:@"template"];
        if (templateId == nil) {
            templateId = _defaultItemTemplate;
        }
        //Ignore built in templates
        if (![templateId isKindOfClass:[NSNumber class]]) {
            TiUIListItem* theCell = [_measureProxies objectForKey:templateId];
            if (theCell != nil) {
                if (item != nil) {
                    theCell.dataItem = item;
                    CGFloat maxWidth = [self computeRowWidth:tableView];
                    if (maxWidth > 0) {

                        CGFloat accessoryAdjustment = 0;
                        int accessoryTypeValue = [TiUtils intValue:[self valueWithKey:@"accessoryType" atIndexPath:realPath] def:0];
                        if (accessoryTypeValue > 0) {
                            if (accessoryTypeValue == UITableViewCellAccessoryDetailDisclosureButton) {
                                accessoryAdjustment = 48.0;
                            } else {
                                accessoryAdjustment = 35.0;
                            }
                            maxWidth -= accessoryAdjustment;
                        }
                    }
                    if (maxWidth > 0) {
                        TiUIListItemProxy* theProxy = [theCell proxy];
                        [theProxy layoutProperties]->height = TiDimensionAutoSize;
                        [theProxy layoutProperties]->width = TiDimensionAutoFill;
                        CGFloat result =  [theProxy minimumParentHeightForSize:CGSizeMake(maxWidth, self.bounds.size.height)];
                        return result;
                    }
                }
                
            } else {
                DebugLog(@"[WARN] Could not retrieve template for SIZE measurement");
            }
        }
    }
    return 44;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self fireClickForItemAtIndexPath:[self pathForSearchPath:indexPath] tableView:tableView accessoryButtonTapped:NO];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self fireClickForItemAtIndexPath:[self pathForSearchPath:indexPath] tableView:tableView accessoryButtonTapped:YES];
}

#pragma mark - ScrollView Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    //Events - pull (maybe scroll later)
    if (![self.proxy _hasListeners:@"pull"]) {
        return;
    }
    
    if ( (_pullViewProxy != nil) && ([scrollView isTracking]) ) {
        if ( (scrollView.contentOffset.y < pullThreshhold) && (pullActive == NO) ) {
            pullActive = YES;
            [self.proxy fireEvent:@"pull" withObject:[NSDictionary dictionaryWithObjectsAndKeys:NUMBOOL(pullActive),@"active",nil] withSource:self.proxy propagate:NO reportSuccess:NO errorCode:0 message:nil];
        } else if ( (scrollView.contentOffset.y > pullThreshhold) && (pullActive == YES) ) {
            pullActive = NO;
            [self.proxy fireEvent:@"pull" withObject:[NSDictionary dictionaryWithObjectsAndKeys:NUMBOOL(pullActive),@"active",nil] withSource:self.proxy propagate:NO reportSuccess:NO errorCode:0 message:nil];
        }
    }
}


// For now, this is fired on `scrollstart` and `scrollend`
- (void)fireScrollEvent:(NSString*)eventName forTableView:(UITableView*)tableView
{
    if([(TiViewProxy*)[self proxy] _hasListeners:eventName checkParent:NO])
    {
        NSArray* indexPaths = [tableView indexPathsForVisibleRows];
        NSMutableDictionary *eventArgs = [NSMutableDictionary dictionary];
        TiUIListSectionProxy* section;
        
        if ([indexPaths count] > 0) {
            NSIndexPath *indexPath = [self pathForSearchPath:[indexPaths objectAtIndex:0]];
            NSUInteger visibleItemCount = [indexPaths count];
            section = [[self listViewProxy] sectionForIndex: [indexPath section]];
            
            [eventArgs setValue:NUMINTEGER([indexPath row]) forKey:@"firstVisibleItemIndex"];
            [eventArgs setValue:NUMUINTEGER(visibleItemCount) forKey:@"visibleItemCount"];
            [eventArgs setValue:NUMINTEGER([indexPath section]) forKey:@"firstVisibleSectionIndex"];
            [eventArgs setValue:section forKey:@"firstVisibleSection"];
            [eventArgs setValue:[section itemAtIndex:[indexPath row]] forKey:@"firstVisibleItem"];
        } else {
            section = [[self listViewProxy] sectionForIndex: 0];
            
            [eventArgs setValue:NUMINTEGER(-1) forKey:@"firstVisibleItemIndex"];
            [eventArgs setValue:NUMUINTEGER(0) forKey:@"visibleItemCount"];
            [eventArgs setValue:NUMINTEGER(0) forKey:@"firstVisibleSectionIndex"];
            [eventArgs setValue:section forKey:@"firstVisibleSection"];
            [eventArgs setValue:NUMINTEGER(-1) forKey:@"firstVisibleItem"];
        }
    
        [[self proxy] fireEvent:eventName withObject:eventArgs propagate:NO];
    }
}

- (void)fireScrollEnd:(UITableView*)tableView
{
    if(canFireScrollEnd) {
        canFireScrollEnd = NO;
        canFireScrollStart = YES;
        [self fireScrollEvent:@"scrollend" forTableView:tableView];
    }
}
- (void)fireScrollStart:(UITableView *)tableView
{
    if(canFireScrollStart) {
        canFireScrollStart = NO;
        canFireScrollEnd = YES;
        [self fireScrollEvent:@"scrollstart" forTableView:tableView];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [[ImageLoader sharedLoader] suspend];
    [self fireScrollStart: (UITableView*)scrollView];
}

- (void)checkBottomState
{
    if ( bReverseMode == true )
    {
    	//DebugLog(@"----[INFO] listView: checkBottomState");
    	
    	int nVisibleRow = 0;
        NSArray *visibleRows = [_tableView indexPathsForVisibleRows];
        
        if ( visibleRows != nil )
        {
            for( int i = 0; i < visibleRows.count; i++ )
            {
                int tempRow = [visibleRows[i] row];
                if ( nVisibleRow < tempRow )
                    nVisibleRow = tempRow;
            }
        }
        if ( _tableView != nil && [_tableView numberOfSections] > 0 )
        {
            if ( nVisibleRow >= ([_tableView numberOfRowsInSection:0]-1)){
                isBottom = true;
            }
            else{
                isBottom = false;
            }
        }
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
	[self checkBottomState];
	
    if(!decelerate) {
        [self fireScrollEnd:(UITableView *)scrollView];
    }
    if (![self.proxy _hasListeners:@"pullend"]) {
        return;
    }
    if ( (_pullViewProxy != nil) && (pullActive == YES) ) {
        pullActive = NO;
        [self.proxy fireEvent:@"pullend" withObject:nil withSource:self.proxy propagate:NO reportSuccess:NO errorCode:0 message:nil];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
	[self checkBottomState];
	
    [[ImageLoader sharedLoader] resume];
    if(isScrollingToTop) {
        isScrollingToTop = NO;
    } else {
        [self fireScrollEnd:(UITableView *)scrollView];
    }
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView
{
    [[ImageLoader sharedLoader] suspend];
    isScrollingToTop = YES;
    [self fireScrollStart:(UITableView*) scrollView];
    return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView
{
    [[ImageLoader sharedLoader] resume];
    [self fireScrollEnd:(UITableView *)scrollView];
    //Events none (maybe scroll later)
}

#pragma mark - UISearchBarDelegate Methods
- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    if (_searchWrapper != nil) {
        [_searchWrapper layoutProperties]->right = TiDimensionDip(0);
        [_searchWrapper refreshView:nil];
        [self initSearchController:self];
    }
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    self.searchString = (searchBar.text == nil) ? @"" : searchBar.text;
    [self buildResultsForSearchText];
    [[searchController searchResultsTableView] reloadData];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    if ([searchBar.text length] == 0) {
        self.searchString = @"";
        [self buildResultsForSearchText];
        if ([searchController isActive]) {
            [searchController setActive:NO animated:YES];
        }
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    self.searchString = (searchText == nil) ? @"" : searchText;
    [self buildResultsForSearchText];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    [self makeRootViewFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *) searchBar
{
    self.searchString = @"";
    [searchBar setText:self.searchString];
    [self buildResultsForSearchText];
}

#pragma mark - UISearchDisplayDelegate Methods

- (void) searchDisplayControllerDidEndSearch:(UISearchDisplayController *)controller
{
    self.searchString = @"";
    [self buildResultsForSearchText];
    if ([searchController isActive]) {
        [searchController setActive:NO animated:YES];
    }
    if (_searchWrapper != nil) {
        CGFloat rowWidth = floorf([self computeRowWidth:_tableView]);
        if (rowWidth > 0) {
            CGFloat right = _tableView.bounds.size.width - rowWidth;
            [_searchWrapper layoutProperties]->right = TiDimensionDip(right);
            [_searchWrapper refreshView:nil];
        }
    }
    //IOS7 DP3. TableView seems to be adding the searchView to
    //tableView. Bug on IOS7?
    [self clearSearchController:self];
    [_tableView reloadData];
}

#pragma mark - TiScrolling

-(void)keyboardDidShowAtHeight:(CGFloat)keyboardTop
{
    CGRect minimumContentRect = [_tableView bounds];
    InsetScrollViewForKeyboard(_tableView,keyboardTop,minimumContentRect.size.height + minimumContentRect.origin.y);
}

-(void)scrollToShowView:(TiUIView *)firstResponderView withKeyboardHeight:(CGFloat)keyboardTop
{
    if ([_tableView isScrollEnabled]) {
        CGRect minimumContentRect = [_tableView bounds];
        
        CGRect responderRect = [self convertRect:[firstResponderView bounds] fromView:firstResponderView];
        CGPoint offsetPoint = [_tableView contentOffset];
        responderRect.origin.x += offsetPoint.x;
        responderRect.origin.y += offsetPoint.y;
        
        OffsetScrollViewForRect(_tableView,keyboardTop,minimumContentRect.size.height + minimumContentRect.origin.y,responderRect);
    }
}


#pragma mark - Internal Methods

- (void)fireClickForItemAtIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView accessoryButtonTapped:(BOOL)accessoryButtonTapped
{
	NSString *eventName = @"itemclick";
    if (![self.proxy _hasListeners:eventName]) {
		return;
	}
	TiUIListSectionProxy *section = [self.listViewProxy sectionForIndex:indexPath.section];
	NSDictionary *item = [section itemAtIndex:indexPath.row];
	NSMutableDictionary *eventObject = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
										section, @"section",
										NUMINTEGER(indexPath.section), @"sectionIndex",
										NUMINTEGER(indexPath.row), @"itemIndex",
										NUMBOOL(accessoryButtonTapped), @"accessoryClicked",
										nil];
	id propertiesValue = [item objectForKey:@"properties"];
	NSDictionary *properties = ([propertiesValue isKindOfClass:[NSDictionary class]]) ? propertiesValue : nil;
	id itemId = [properties objectForKey:@"itemId"];
	if (itemId != nil) {
		[eventObject setObject:itemId forKey:@"itemId"];
	}
	TiUIListItem *cell = (TiUIListItem *)[tableView cellForRowAtIndexPath:indexPath];
	if (cell.templateStyle == TiUIListItemTemplateStyleCustom) {
		UIView *contentView = cell.contentView;
		TiViewProxy *tapViewProxy = FindViewProxyWithBindIdContainingPoint(contentView, [tableView convertPoint:tapPoint toView:contentView]);
		if (tapViewProxy != nil) {
			[eventObject setObject:[tapViewProxy valueForKey:@"bindId"] forKey:@"bindId"];
		}
	}
	[self.proxy fireEvent:eventName withObject:eventObject];
	[eventObject release];	
}

-(CGFloat)contentWidthForWidth:(CGFloat)width
{
    return width;
}

-(CGFloat)contentHeightForWidth:(CGFloat)width
{
    if (_tableView == nil) {
        return 0;
    }
    
    CGSize refSize = CGSizeMake(width, 1000);
    
    CGFloat resultHeight = 0;
    
    //Last Section rect
    NSInteger lastSectionIndex = [self numberOfSectionsInTableView:_tableView] - 1;
    if (lastSectionIndex >= 0) {
        CGRect refRect = [_tableView rectForSection:lastSectionIndex];
        resultHeight += refRect.size.height + refRect.origin.y;
    } else {
        //Header auto height when no sections
        if (_headerViewProxy != nil) {
            resultHeight += [_headerViewProxy autoHeightForSize:refSize];
        }
    }
    
    //Footer auto height
    if (_footerViewProxy) {
        resultHeight += [_footerViewProxy autoHeightForSize:refSize];
    }
    
    return resultHeight;
}

-(void)clearSearchController:(id)sender
{
    if (sender == self) {
        RELEASE_TO_NIL(tableController);
        RELEASE_TO_NIL(searchController);
        [searchViewProxy ensureSearchBarHeirarchy];
    }
}

-(void)initSearchController:(id)sender
{
    if (sender == self && tableController == nil) {
        tableController = [[UITableViewController alloc] init];
        [TiUtils configureController:tableController withObject:nil];
        tableController.tableView = [self tableView];
        searchController = [[UISearchDisplayController alloc] initWithSearchBar:[searchViewProxy searchBar] contentsController:tableController];
        searchController.searchResultsDataSource = self;
        searchController.searchResultsDelegate = self;
        searchController.delegate = self;
    }
}

#pragma mark - UITapGestureRecognizer

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
	tapPoint = [gestureRecognizer locationInView:gestureRecognizer.view];
	return NO;
}

- (void)handleTap:(UITapGestureRecognizer *)tapGestureRecognizer
{
	// Never called
}

#pragma mark - Static Methods

+ (void)setBackgroundColor:(TiColor*)color onTable:(UITableView*)table
{
	UIColor* defaultColor = [table style] == UITableViewStylePlain ? [UIColor whiteColor] : [UIColor groupTableViewBackgroundColor];
	UIColor* bgColor = [color _color];
	
	// WORKAROUND FOR APPLE BUG: 4.2 and lower don't like setting background color for grouped table views on iPad.
	// So, we check the table style and device, and if they match up wrong, we replace the background view with our own.
	if (([table style] == UITableViewStyleGrouped) && [TiUtils isIPad]) {
		UIView* bgView = [[[UIView alloc] initWithFrame:[table frame]] autorelease];
		[table setBackgroundView:bgView];
	}
	
	[table setBackgroundColor:(bgColor != nil ? bgColor : defaultColor)];
	[[table backgroundView] setBackgroundColor:[table backgroundColor]];
	
	[table setOpaque:![[table backgroundColor] isEqual:[UIColor clearColor]]];
}

+ (TiViewProxy*)titleViewForText:(NSString*)text inTable:(UITableView *)tableView footer:(BOOL)footer
{
    TiUILabelProxy* titleProxy = [[TiUILabelProxy alloc] init];
    [titleProxy setValue:[NSDictionary dictionaryWithObjectsAndKeys:@"17",@"fontSize",@"bold",@"fontWeight", nil] forKey:@"font"];
    [titleProxy setValue:text forKey:@"text"];
    [titleProxy setValue:@"black" forKey:@"color"];
    [titleProxy setValue:@"white" forKey:@"shadowColor"];
    [titleProxy setValue:[NSDictionary dictionaryWithObjectsAndKeys:@"0",@"x",@"1",@"y", nil] forKey:@"shadowOffset"];
    
    LayoutConstraint *viewLayout = [titleProxy layoutProperties];
    viewLayout->width = TiDimensionAutoFill;
    viewLayout->height = TiDimensionAutoSize;
    viewLayout->top = TiDimensionDip(10.0);
    viewLayout->bottom = TiDimensionDip(10.0);
    viewLayout->left = ([tableView style] == UITableViewStyleGrouped) ? TiDimensionDip(15.0) : TiDimensionDip(10.0);
    viewLayout->right = ([tableView style] == UITableViewStyleGrouped) ? TiDimensionDip(15.0) : TiDimensionDip(10.0);

    return [titleProxy autorelease];
}

+ (UITableViewRowAnimation)animationStyleForProperties:(NSDictionary*)properties
{
	BOOL found;
	UITableViewRowAnimation animationStyle = [TiUtils intValue:@"animationStyle" properties:properties def:UITableViewRowAnimationNone exists:&found];
	if (found) {
		return animationStyle;
	}
	BOOL animate = [TiUtils boolValue:@"animated" properties:properties def:NO];
	return animate ? UITableViewRowAnimationFade : UITableViewRowAnimationNone;
}

@end

static TiViewProxy * FindViewProxyWithBindIdContainingPoint(UIView *view, CGPoint point)
{
    if (!CGRectContainsPoint([view bounds], point)) {
        return nil;
    }
    for (int i = (int)[view.subviews count]-1; i >=0; i--){
        UIView *subview = [view.subviews objectAtIndex:i];
        TiViewProxy *viewProxy = FindViewProxyWithBindIdContainingPoint(subview, [view convertPoint:point toView:subview]);
        if (viewProxy != nil) {
            id bindId = [viewProxy valueForKey:@"bindId"];
            if (bindId != nil) {
                return viewProxy;
            }
        }
    }
    if ([view isKindOfClass:[TiUIView class]]) {
        TiViewProxy *viewProxy = (TiViewProxy *)[(TiUIView *)view proxy];
        id bindId = [viewProxy valueForKey:@"bindId"];
        if (bindId != nil) {
            return viewProxy;
        }
    }
    return nil;
}

#endif
