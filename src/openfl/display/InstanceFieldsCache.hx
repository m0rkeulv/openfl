package openfl.display;
/**
	Since `Reflect.hasField()` is only works properly for anonymous structures, we will have to keep track of
	instance fields manually. This class helps caching `Type.getInstanceFields()` results and also removes unnecessary
	fields.

	The unnecessary fields removal is currently very basic and just removes all known `MovieClip` fields,
	any method or property that has been added to a class that extends MovieClip will be included even if  its a
	`Void->Void` or use data types that are not displayObjects

**/
class InstanceFieldsCache {

    private static final __instanceFieldCache:Map<String,Array<String>> = new Map();
    private static final __emptyArray:Array<String> = new Array();

    private static final __openFlMovieclipFields:Array<String> = Type.getInstanceFields(Type.getClass(new MovieClip()));

    public static function getInstanceFields(object:Any):Array<String> {

        var classObject = Type.getClass(object);
        var className = Type.getClassName(classObject);

        if (!__instanceFieldCache.exists(className))
        {
            var instanceFields = Type.getInstanceFields(classObject);
            instanceFields = removeNonNessesaryFields(instanceFields);
            if(instanceFields.length > 0)
            {
                __instanceFieldCache.set(className, instanceFields);
            }
            else
            {
                // no need to create multiple empty arrays, so we will just reuse one
                __instanceFieldCache.set(className, __emptyArray);
            }

        }


       return __instanceFieldCache.get(className);
    }

    private static function removeNonNessesaryFields(fields:Array<String>):Array<String>
    {
        var fieldCount = 0;
        var fieldArray = new Array();
        fieldArray.resize(fields.length - __openFlMovieclipFields.length);
        for(field in fields) {
			if(!InstanceFieldsCache.__openFlMovieclipFields.contains(field)) {
                fieldArray[fieldCount++] = field;
			}
        }
        if(fieldCount<fieldArray.length)fieldArray.resize(fieldCount);
        return fieldArray;
    }



}
