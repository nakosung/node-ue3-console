class ScriptHost extends TcpLink
	native;

function PostBeginPlay()
{
	Super.PostBeginPlay();

	// Cannot be set within defaultproperties, because it is over-written in AInternetLink::ctor()
	LinkMode = MODE_Line;

	if (BindPort(1336) > 0)
	{
		if (Listen())
		{
			return;
		}
	}

	Destroy();
}

event Accepted()
{
	`log("accepted");

	SendText( "Welcome, UnrealEngine3 + Node.JS" );
}

native function Object ImportObjectProperty( string ObjectName );

function Object GetObject( string ObjectName )
{
	switch (ObjectName)
	{
	case "WorldInfo" : return WorldInfo;
	case "GameInfo" : return WorldInfo.Game;
	case "LocalPC" : return WorldInfo.GetALocalPlayerController();		
	case "self" : return self;
	default : return ImportObjectProperty(ObjectName);
	}	
}

native function class GetSuperClass( class ClassObject );
native function string ExecuteFunction( Object obj, string Command );
native function array<string> GetPropertyNames( Object obj, bool bIncludeSuper );
native function array<string> GetFunctionNames( Object obj, bool bIncludeSuper );
native function string ExportProperty( Object obj, const out array<name> keys, const out array<int> indices );
native function bool ImportProperty( Object obj, const out array<name> keys, const out array<int> indices, string value );
function string ReadProperty( Object obj, string Key )
{
	local array<name> Names;
	local array<int> Indices;
	
	ParsePropertyLocationString(Key,Names,Indices);
	
	return ExportProperty(obj,names,indices);
}
function bool WriteProperty( Object obj, string Key, string Value )
{
	local array<name> Names;
	local array<int> Indices;
	
	ParsePropertyLocationString(Key,Names,Indices);
	
	return ImportProperty(obj,names,indices,Value);
}

static function ParsePropertyLocationString( string Loc, out array<name> Names, out array<int> Indices )
{
	local array<string> StringNames;
	local int i, j;	

	StringNames = SplitString(loc,".");

	for (i=0; i<StringNames.Length; ++i)
	{
		j = InStr(StringNames[i],"[");
		if (j >= 0)
		{
			Names.AddItem( name(Left(StringNames[i],j)) );
			Indices.AddItem(int(Mid(StringNames[i], j+1, InStr(StringNames[i],"]") - j - 1)));
		}
		else
		{
			Names.AddItem( name(StringNames[i]) );
			Indices.AddItem(0);
		}
	}
}

function string GetClassName( class ClassObject )
{
	return (ClassObject != None) ? ("class'" $ string(ClassObject.Outer) $ "." $ string(ClassObject) $"'") : "None";
}

event ReceivedLine( string Text )
{
	local Object obj;
	local int delim;	
	local int trid;
	local string action, key, result;

	`log(self@GetFuncName()@Text);

	delim = InStr(Text," ");
	trid = int(Mid(Text,0,delim));
	Text = Mid(Text,delim+1);

	delim = InStr(Text," ");
	obj = GetObject(Mid(Text,0,delim));
	Text = Mid(Text,delim+1);
	if (obj != None)
	{		
		delim = InStr(Text," ");
		action = Mid(Text,0,delim);
		Text = Mid(Text,delim+1);

		if (action == "exec")
		{			
			result = ExecuteFunction(obj,Text);
			`log( "result"@result );
			SendText( trid @ result );
		}
		else if (action == "class")
		{			
			SendText( trid @ GetClassName(obj.Class) );
		}		
		else if (action == "super")
		{			
			SendText( trid @ GetClassName(GetSuperClass(class(obj))));
		}
		else if (action == "listprop")
		{
			JoinArray(GetPropertyNames(class(obj),false),text);
			SendText( trid@text );
		}
		else if (action == "listfunc")
		{
			JoinArray(GetFunctionNames(class(obj),false),text);
			SendText( trid@text );
		}
		else if (action == "read")
		{			
			SendText( trid@ReadProperty(obj,Text) );
		}
		else if (action == "write")
		{
			delim = InStr(Text," ");
			key = Mid(Text,0,delim);
			Text = Mid(Text,delim+1);

			SendText( trid@WriteProperty(obj,key,Text) );
		}
	}	
}

