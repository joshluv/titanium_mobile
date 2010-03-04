/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiViewProxy.h"
#import "LayoutConstraint.h"
#import "TitaniumApp.h"
#import "TiBlob.h"
#import "TiRect.h"
#import <QuartzCore/QuartzCore.h>


@implementation TiViewProxy

@synthesize children, parent;

#pragma mark Internal

-(void)dealloc
{
	if (view!=nil)
	{
		view.proxy = nil;
	}
	RELEASE_TO_NIL(view);
	RELEASE_TO_NIL(children);
	RELEASE_TO_NIL(childLock);
	[super dealloc];
}

#pragma mark Subclass Callbacks 

-(void)childAdded:(id)child
{
}

-(void)childRemoved:(id)child
{
}

-(void)layoutChildOnMainThread:(id)arg
{
	ENSURE_UI_THREAD(layoutChildOnMainThread,arg);
	[self layoutChild:arg]; 
}

#pragma mark Public

-(void)add:(id)arg
{
	ENSURE_SINGLE_ARG(arg,TiViewProxy);
	if (childLock==nil)
	{
		// since we can have multiple threads (one for JS context, one for UI thread)
		// we need to (unfortunately) lock
		childLock = [[NSRecursiveLock alloc] init];
	}
	[childLock lock];
	if (children==nil)
	{
		children = [[NSMutableArray alloc] init];
	}
	[children addObject:arg];
	[arg setParent:self];
	// only call layout if the view is attached
	if ([self viewAttached])
	{
		[self layoutChildOnMainThread:arg];
	}
	[self childAdded:arg];
	[childLock unlock];
}


-(void)remove:(id)arg
{
	ENSURE_SINGLE_ARG(arg,TiViewProxy);
	if (children!=nil)
	{
		[childLock lock];
		[self childRemoved:arg];
		[children removeObject:arg];
		[arg setParent:nil];
		
		if ([children count]==0)
		{
			RELEASE_TO_NIL(children);
		}
		[childLock unlock];
	}
	if (view!=nil)
	{
		TiUIView *childView = [(TiViewProxy *)arg view];
		BOOL verticalNeedsRearranging = TiLayoutRuleIsVertical([view layoutProperties]->layout);
		if ([NSThread isMainThread])
		{
			[childView removeFromSuperview];
			if (verticalNeedsRearranging)
			{
				[self layoutChildren];
			}
		}
		else
		{
			[self performSelectorOnMainThread:@selector(removeFromSuperview) withObject:childView waitUntilDone:NO];
			if (verticalNeedsRearranging)
			{
				[self performSelectorOnMainThread:@selector(layout) withObject:nil waitUntilDone:NO];
			}
		}
	}
}

-(TiPoint*)center
{
	return [[[TiPoint alloc] initWithPoint:[self view].center] autorelease];
}

-(void)show:(id)arg
{
	//TODO: animate
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"visible"];
}
 
-(void)hide:(id)arg
{
	//TODO: animate
	[self setValue:[NSNumber numberWithBool:NO] forKey:@"visible"];
}

-(void)animate:(id)arg
{
	ENSURE_UI_THREAD(animate,arg);
	[[self view] animate:arg];
}

-(void)addImageToBlob:(NSArray*)args
{
	TiBlob *blob = [args objectAtIndex:0];
	UIView *myview = [self view];
	UIGraphicsBeginImageContext(myview.bounds.size);
	[myview.layer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	[blob setImage:image];
	UIGraphicsEndImageContext();
	if ([args count] > 1)
	{
		KrollCallback *callback = [args objectAtIndex:1];
		NSDictionary *event = [NSDictionary dictionaryWithObject:blob forKey:@"blob"];
		[self _fireEventToListener:@"blob" withObject:event listener:callback thisObject:nil];
	}
}

-(TiBlob*)toImage:(id)args
{
	KrollCallback *callback = [args count] > 0 ? [args objectAtIndex:0] : nil;
	TiBlob *blob = [[[TiBlob alloc] init] autorelease];
	// we spin on the UI thread and have him convert and then add back to the blob
	// if you pass a callback function, we'll run the render asynchronously, if you
	// don't, we'll do it synchronously
	[self performSelectorOnMainThread:@selector(addImageToBlob:) withObject:[NSArray arrayWithObjects:blob,callback,nil] waitUntilDone:callback==nil ? YES : NO];
	return blob;
}

#pragma mark View


-(TiRect*)size
{
	TiRect *rect = [[[TiRect alloc] init] autorelease];
	[[self view] performSelectorOnMainThread:@selector(fillBoundsToRect:) withObject:rect waitUntilDone:YES];
	return rect;
}

-(void)setParent:(TiViewProxy*)parent_
{
	parent = parent_;
	if (view!=nil)
	{
		[view setParent:parent_];
	}
}

-(void)animationCompleted:(TiAnimation*)animation
{
	[[self view] animationCompleted];
}

-(TiUIView*)newView
{
	NSString * proxyName = NSStringFromClass([self class]);
	if ([proxyName hasSuffix:@"Proxy"]) 
	{
		Class viewClass = nil;
		NSString * className = [proxyName substringToIndex:[proxyName length]-5];
		viewClass = NSClassFromString(className);
		if (viewClass != nil)
		{
			return [[viewClass alloc] init];
		}
	}

	return [[TiUIView alloc] initWithFrame:[self appFrame]];
}

-(BOOL)viewAttached
{
	return view!=nil;
}

-(void)detachView
{
	if (view!=nil)
	{
		[self viewWillDetach];
		view.proxy = nil;
		[view removeFromSuperview];
		[self viewDidDetach];
		self.modelDelegate = nil;
		RELEASE_TO_NIL(view);
	}
}

-(void)windowDidClose
{
	if (children!=nil)
	{
		[childLock lock];
		for (TiViewProxy *child in children)
		{
			[child windowDidClose];
		}
		[childLock unlock];
	}
}

-(void)windowWillClose
{
	if (children!=nil)
	{
		[childLock lock];
		for (TiViewProxy *child in children)
		{
			[child windowWillClose];
		}
		[childLock unlock];
	}
	[self detachView];
}

-(void)viewWillAttach
{
	// for subclasses
}

-(void)viewDidAttach
{
	// for subclasses
}

-(void)viewWillDetach
{
	// for subclasses
}

-(void)viewDidDetach
{
	// for subclasses
}

-(void)willFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(willFirePropertyChanges)])
	{
		[view performSelector:@selector(willFirePropertyChanges)];
	}
}

-(void)didFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(didFirePropertyChanges)])
	{
		[view performSelector:@selector(didFirePropertyChanges)];
	}
}

-(BOOL)viewReady
{
	return view!=nil && 
			CGRectIsEmpty(view.bounds)==NO && 
			CGRectIsNull(view.bounds)==NO &&
			[view superview] != nil;
}

-(BOOL)viewInitialized
{
	return viewInitialized;
}

-(void)firePropertyChanges
{
	[self willFirePropertyChanges];
	
	id<NSFastEnumeration> values = [self validKeys];
	if (values == nil)
	{
		values = [dynprops allKeys];
	}
	
	[view readProxyValuesWithKeys:values];

	[self didFirePropertyChanges];
}

-(void)exchangeView:(TiUIView*)newview
{
	//NOTE: this is dangerous and should only be called
	//when you know what the heck you intend to do.
	//used by tableview currently for view swapping
	if (view!=nil)
	{
		view.proxy = nil;
		RELEASE_TO_NIL(view);
	}
	view = [newview retain];
	view.proxy = self;
}

-(TiUIView*)view
{
	if (view == nil)
	{
		[self viewWillAttach];
		
		// on open we need to create a new view
		view = [self newView];
		view.proxy = self;
		view.parent = parent;
		view.layer.transform = CATransform3DIdentity;
		view.transform = CGAffineTransformIdentity;

		[view initializeState];

		[view willSendConfiguration];

		// fire property changes for all properties to our delegate
		[self firePropertyChanges];

		[view didSendConfiguration];

		[view configurationSet];
		
		if (children!=nil)
		{
			[childLock lock];
			for (id child in self.children)
			{
				TiUIView *childView = [(TiViewProxy*)child view];
				//[childView setParent:self];
				[view addSubview:childView];
			}
			[childLock unlock];
		}

		[self viewDidAttach];

		// make sure we do a layout of ourselves
//		LayoutConstraint layout;
//		ReadConstraintFromDictionary(&layout,[self allProperties]);
		[view updateLayout:NULL withBounds:view.bounds];
		
		viewInitialized = YES;
	}
	return view;
}

#pragma mark Layout 

-(void)layoutChild:(TiViewProxy*)child;
{
	if (view==nil)
	{
		return;
	}

	CGRect bounds = [view bounds];

	// layout out ourself
	UIView *childView = [child view];

	if ([childView superview]!=view)
	{
		[view addSubview:childView];
	}
	
//	LayoutConstraint ourLayoutConstraint;
//	ReadConstraintFromDictionary(&ourLayoutConstraint,[child allProperties]);

	if(TiLayoutRuleIsVertical(layoutProperties.layout)){
		bounds.origin.y += verticalLayoutBoundary;
		bounds.size.height = [child minimumParentHeightForWidth:bounds.size.width];
		verticalLayoutBoundary += bounds.size.height;
	}

//	[child setLayoutProperties:<#(LayoutConstraint *)#>

	[[child view] updateLayout:NULL withBounds:bounds];
	
	// tell our children to also layout
	[child layoutChildren];
}

-(void)layoutChildren
{
	verticalLayoutBoundary = 0.0;
	// now ask each of our children for their view
	if (view==nil)
	{
		return;
	}
	if (self.children!=nil)
	{
		[childLock lock];
		for (id child in self.children)
		{
			[self layoutChild:child];
		}
		[childLock unlock];
	}
}

-(CGRect)appFrame
{
	return [[UIScreen mainScreen] applicationFrame];
}

#pragma mark Memory Management

-(void)_destroy
{
	if (view!=nil)
	{
		view.proxy = nil;
		[view removeFromSuperview];
		RELEASE_TO_NIL(view);
	}
	if (children!=nil)
	{
		[childLock lock];
		[children removeAllObjects];
		[childLock unlock];
		RELEASE_TO_NIL(children);
	}
	[super _destroy];
}

-(void)destroy
{
	//FIXME- me already have a _destroy, refactor this
	[self _destroy];
}

#pragma mark Listener Management

-(BOOL)_hasListeners:(NSString *)type
{
	if ([super _hasListeners:type])
	{
		return YES;
	}
	// check our parent since we optimize the fire with
	// the check
	if (parent!=nil)
	{
		// walk up the chain
		return [parent _hasListeners:type];
	}
	return NO;
}

-(void)fireEvent:(NSString*)type withObject:(id)obj withSource:(id)source propagate:(BOOL)propagate
{
	[super fireEvent:type withObject:obj withSource:source propagate:YES];
	
	// views support event propagation. we need to check our
	// parent and if he has the same named listener, we fire
	// an event and set the source of the event to ourself
	if (parent!=nil && propagate==YES)
	{
		[parent fireEvent:type withObject:obj withSource:source];
	}
}

-(void)_listenerAdded:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil && [(NSObject*)self.modelDelegate respondsToSelector:@selector(listenerAdded:count:)])
	{
		[self.modelDelegate listenerAdded:type count:count];
	}
}

-(void)_listenerRemoved:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil && [(NSObject*)self.modelDelegate respondsToSelector:@selector(listenerRemoved:count:)])
	{
		[self.modelDelegate listenerRemoved:type count:count];
	}
}

#pragma mark For Nav Bar Support

-(BOOL)supportsNavBarPositioning
{
	return NO;
}

- (TiUIView *)barButtonViewForSize:(CGSize)bounds
{
	return nil;
}

-(UIBarButtonItem*)barButtonItem
{
	return nil;
}

-(void)removeBarButtonView
{
	// called to remove
}

#pragma mark For autosizing of table views

-(LayoutConstraint *)layoutProperties
{
	return &layoutProperties;
}

-(void)setLayoutProperties:(LayoutConstraint *)newLayout
{
	layoutProperties = *newLayout;
}


-(CGFloat)autoWidthForWidth:(CGFloat)suggestedWidth
{
	CGFloat result = 0.0;
	for (TiViewProxy * thisChildProxy in children)
	{
		result = MAX(result,[thisChildProxy minimumParentWidthForWidth:suggestedWidth]);
	}
	return MIN(suggestedWidth,result);
//	return MIN(suggestedWidth,AutoWidthForView([self view], suggestedWidth));
}

-(CGFloat)autoHeightForWidth:(CGFloat)width
{
	BOOL isVertical = TiLayoutRuleIsVertical(layoutProperties.layout);
	CGFloat result=0.0;

	for (TiViewProxy * thisChildProxy in children)
	{
		CGFloat thisHeight = [thisChildProxy minimumParentHeightForWidth:width];
		if (isVertical)
		{
			result += thisHeight;
		}
		else if(result<thisHeight)
		{
			result = thisHeight;
		}
	}
	return result;
}

-(CGFloat)minimumParentWidthForWidth:(CGFloat)suggestedWidth
{
	CGFloat result = TiDimensionCalculateValue(layoutProperties.left, 0)
			+ TiDimensionCalculateValue(layoutProperties.right, 0);
	if (TiDimensionIsPixels(layoutProperties.width))
	{
		result += layoutProperties.width.value;
	}
	else if(TiDimensionIsAuto(layoutProperties.width))
	{
		result += [self autoWidthForWidth:suggestedWidth - result];
	}
	return result;
}

-(CGFloat)minimumParentHeightForWidth:(CGFloat)suggestedWidth
{
//	if ([self viewAttached])
//	{
//		//Since it's expensive to extract from properties, let's cheat if the view already is there.
//		return [view minimumParentHeightForWidth:suggestedWidth];
//	}

	CGFloat result = TiDimensionCalculateValue(layoutProperties.top, 0)
			+ TiDimensionCalculateValue(layoutProperties.bottom, 0);

	if (TiDimensionIsPixels(layoutProperties.height))
	{
		result += layoutProperties.height.value;
	}
	else if(TiDimensionIsAuto(layoutProperties.height))
	{
		result += [self autoHeightForWidth:TiDimensionCalculateMargins(layoutProperties.left, layoutProperties.right, suggestedWidth)];
	}
	return result;
}


-(void)reposition
{
	if (![self viewAttached])
	{
		return;
	}
	if ([NSThread isMainThread])
	{	//NOTE: This will cause problems with ScrollableView, or is a new wrapper needed?
		[[self view] relayout:[[self view] superview].bounds];
	}
	else 
	{
		[self performSelectorOnMainThread:@selector(reposition) withObject:nil waitUntilDone:NO];
	}

}

#define LAYOUTPROPERTIES_SETTER(methodName,layoutName,converter)	\
-(void)methodName:(id)value	\
{	\
	layoutProperties.layoutName = converter(value);	\
	[self reposition];	\
	[self replaceValue:value forKey:@#layoutName notification:YES];	\
}

LAYOUTPROPERTIES_SETTER(setTop,top,TiDimensionFromObject)
LAYOUTPROPERTIES_SETTER(setBottom,bottom,TiDimensionFromObject)

LAYOUTPROPERTIES_SETTER(setLeft,left,TiDimensionFromObject)
LAYOUTPROPERTIES_SETTER(setRight,right,TiDimensionFromObject)

LAYOUTPROPERTIES_SETTER(setWidth,width,TiDimensionFromObject)
LAYOUTPROPERTIES_SETTER(setHeight,height,TiDimensionFromObject)

LAYOUTPROPERTIES_SETTER(setLayout,layout,TiLayoutRuleFromObject)

-(void)setCenter:(id)value
{
	if (![value isKindOfClass:[NSDictionary class]])
	{
		layoutProperties.centerX = TiDimensionUndefined;
		layoutProperties.centerY = TiDimensionUndefined;
	}
	else
	{
		layoutProperties.centerX = TiDimensionFromObject([value objectForKey:@"x"]);
		layoutProperties.centerY = TiDimensionFromObject([value objectForKey:@"y"]);
	}
	[self reposition];
}


@end
