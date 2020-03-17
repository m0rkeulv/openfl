package openfl.utils;
#if cpp
class WeakRefrence<T> {
	var isWeak:Bool;
	var strongRef:T;
	var weakRef:cpp.vm.WeakRef<T>;

	public function new(inObject:T, weak:Bool) {
		isWeak = weak;
		if (isWeak)
			weakRef = new cpp.vm.WeakRef(inObject);
		else
			strongRef = inObject;
	}

	public function get():T {
		if (isWeak)
			return weakRef.get();

		return strongRef;
	}

}
#else
//Weak refrences currently only supported for cpp target
class WeakRefrence<T> {
	var ref:T;

	public function new(inObject:T, weak:Bool) {
		ref = inObject;
	}

	public function get():T {
		return ref;

	}
}
#end
