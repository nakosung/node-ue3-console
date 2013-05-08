IMPLEMENT_CLASS(AScriptHost)

UClass* AScriptHost::GetSuperClass( UClass* Class )
{
	return Class ? Class->GetSuperClass() : NULL;
}

class UObject* AScriptHost::ImportObjectProperty(const FString& ObjectName)
{
	UProperty* Property = Cast<UProperty>(UProperty::StaticClass()->ClassDefaultObject);
	UObject* Ptr;

	const TCHAR* InBuffer = *ObjectName;
	if (UObjectProperty::ParseObjectPropertyValue(Property,this,UObject::StaticClass(),0,InBuffer,Ptr))
	{
		return Ptr;
	}
	else
	{
		return NULL;
	}
}

TArray<FString> AScriptHost::GetPropertyNames( UObject* Object, UBOOL bIncludeSuper )
{
	TArray<FString> Result;

	UStruct* Struct = Cast<UStruct>(Object);
	
	for (TFieldIterator<UProperty> It(Struct,bIncludeSuper); It; ++It)
	{
		Result.AddItem((*It)->GetName());
	}

	return Result;
}

TArray<FString> AScriptHost::GetFunctionNames( UObject* Object, UBOOL bIncludeSuper )
{
	TArray<FString> Result;

	UStruct* Struct = Cast<UStruct>(Object);

	for (TFieldIterator<UFunction> It(Struct,bIncludeSuper); It; ++It)
	{
		Result.AddItem((*It)->GetName());
	}

	return Result;
}

UBOOL LocateProperty( UObject*& Obj, const TArray<FName>& Keys,const TArray<INT>& Indices, UProperty*& FinalProperty, BYTE*& PropertyData )
{
	UStruct* Template = Obj->GetClass();
	BYTE* SourceAddress = (BYTE*)Obj;

	for (INT Index=0; Index < Keys.Num() && Index < Indices.Num(); ++Index)
	{
		for (TFieldIterator<UProperty> It(Template); It; ++It)
		{
			if (It->GetFName() == Keys(Index))
			{
				UProperty* Property = *It;

				BYTE* PropAddr = SourceAddress + Property->Offset;
				BYTE* Data = PropAddr + Property->ElementSize * Indices(Index);

				UBOOL bReachedEnd = Index == (Keys.Num() - 1);

				if (bReachedEnd)
				{
					FinalProperty = Property;						
					PropertyData = Data;
					return TRUE;					
				}				

				UObjectProperty* ObjectProperty = Cast<UObjectProperty>(Property);
				if (ObjectProperty)
				{
					UObject* Object = *(UObject**)Data;

					if (Object && !Object->IsPendingKill())
					{
						Obj = Object;
						Template = Obj->GetClass();
						SourceAddress = (BYTE*)Obj;
					}
					else 
					{
						Obj = NULL;
						Template = NULL;
						SourceAddress = NULL;						
					}
				}

				UStructProperty* StructProperty = Cast<UStructProperty>(Property);
				if (StructProperty)
				{
					UStruct* Struct = StructProperty->Struct;
					Template = Struct;
					SourceAddress = Data;
				}				
			}
		}				
	}

	return FALSE;
}

static FString ExportProperty2( UObject* Obj, UProperty* Property, BYTE* Data )
{
	FString ValueString;		
	Property->ExportTextItem(ValueString,Data,NULL,Obj,0);

	return ValueString;	
}

FString AScriptHost::ExportProperty(UObject* Obj,const TArray<FName>& Keys,const TArray<INT>& Indices)
{
	UProperty* Property;
	BYTE* Data;
	if (LocateProperty(Obj,Keys,Indices,Property,Data))
	{
		return ExportProperty2(Obj,Property,Data);
	}

	return TEXT("undefined");
}

UBOOL AScriptHost::ImportProperty(UObject* Obj,const TArray<FName>& Keys,const TArray<INT>& Indices,const FString& Value)
{
	UProperty* Property;
	BYTE* Data;
	if (LocateProperty(Obj,Keys,Indices,Property,Data))
	{
		FString ValueString;		
		Property->ImportText(*Value,Data,0,NULL);

		return TRUE;		
	}	

	return FALSE;
}

FString AScriptHost::ExecuteFunction( UObject* Executor, const FString& Command )
{
	const TCHAR* Str = *Command;

	// Find UnrealScript exec function.
	FString MsgStr;
	FName Message = NAME_None;
	UFunction* Function = NULL;
	if
		(	!ParseToken(Str,MsgStr,TRUE)
		||	(Message=FName(*MsgStr,FNAME_Find))==NAME_None
		||	(Function=Executor->FindFunction(Message))==NULL
		/*||	(Function->FunctionFlags & FUNC_Exec) == 0 */)
	{
		return TEXT("undefined");
	}

	UProperty* LastParameter=NULL;

	// find the last parameter
	for ( TFieldIterator<UProperty> It(Function); It && (It->PropertyFlags&(CPF_Parm|CPF_ReturnParm)) == CPF_Parm; ++It )
	{
		LastParameter = *It;
	}

	UStrProperty* LastStringParameter = Cast<UStrProperty>(LastParameter);


	// Parse all function parameters.
	BYTE* Parms = (BYTE*)appAlloca(Function->ParmsSize);
	appMemzero( Parms, Function->ParmsSize );

	// if this exec function has optional parameters, we'll need to process the default value opcodes
	FFrame* ExecFunctionStack=NULL;
	if ( Function->HasAnyFunctionFlags(FUNC_HasOptionalParms) )
	{
		ExecFunctionStack = new FFrame( this, Function, 0, Parms, NULL );
		// set the runtime flag so we can evaluate defaults for any optionals
		GRuntimeUCFlags |= RUC_SkippedOptionalParm;
	}

	UBOOL Failed = 0;
	INT NumParamsEvaluated = 0;
	for( TFieldIterator<UProperty> It(Function); It && (It->PropertyFlags & (CPF_Parm|CPF_ReturnParm))==CPF_Parm; ++It, NumParamsEvaluated++ )
	{
		BYTE* CurrentPropAddress = Parms + It->Offset;

		if ( It->HasAnyPropertyFlags(CPF_OptionalParm) )
		{
			checkSlow(ExecFunctionStack);
			if ( Function->HasAnyFunctionFlags(FUNC_HasDefaults) )
			{
				UStructProperty* StructProp = Cast<UStructProperty>(*It, CLASS_IsAUStructProperty);
				if ( StructProp != NULL )
				{
					StructProp->InitializeValue(CurrentPropAddress);
				}
			}
			ExecFunctionStack->Step(ExecFunctionStack->Object, CurrentPropAddress);
		}

		if( NumParamsEvaluated == 0 && Executor )
		{
			UObjectProperty* Op = Cast<UObjectProperty>(*It,CLASS_IsAUObjectProperty);
			if( Op && Executor->IsA(Op->PropertyClass) )
			{
				// First parameter is implicit reference to object executing the command.
				*(UObject**)(Parms + It->Offset) = Executor;
				continue;
			}
		}

		ParseNext( &Str );

		DWORD ExportFlags = PPF_Localized;

		// if this is the last parameter of the exec function and it's a string, make sure that it accepts the remainder of the passed in value
		if ( LastStringParameter != *It )
		{
			ExportFlags |= PPF_Delimited;
		}
		const TCHAR* PreviousStr = Str;
		const TCHAR* Result = It->ImportText( Str, Parms+It->Offset, ExportFlags, NULL );
		UBOOL bFailedImport = (Result == NULL || Result == PreviousStr);
		if( bFailedImport )
		{
			if( !It->HasAnyPropertyFlags(CPF_OptionalParm) )
			{
				warnf( LocalizeSecure(LocalizeError(TEXT("BadProperty"),TEXT("Core")), *Message.ToString(), *It->GetName()) );
				Failed = TRUE;
			}

			// still need to process the remainder of the optional default values
			if ( ExecFunctionStack != NULL )
			{
				for ( ++It; It; ++It )
				{
					if ( !It->HasAnyPropertyFlags(CPF_Parm) || It->HasAnyPropertyFlags(CPF_ReturnParm) )
					{
						break;
					}

					if ( It->HasAnyPropertyFlags(CPF_OptionalParm) )
					{
						BYTE* CurrentPropAddress = Parms + It->Offset;

						if ( Function->HasAnyFunctionFlags(FUNC_HasDefaults) )
						{
							UStructProperty* StructProp = Cast<UStructProperty>(*It, CLASS_IsAUStructProperty);
							if ( StructProp != NULL )
							{
								StructProp->InitializeValue(CurrentPropAddress);
							}
						}
						ExecFunctionStack->Step(ExecFunctionStack->Object, CurrentPropAddress);
					}
				}
			}
			break;
		}

		// move to the next parameter
		Str = Result;
	}

	// reset the runtime flag
	GRuntimeUCFlags &= ~RUC_SkippedOptionalParm;

	FString ResultString = TEXT("undefined");

	if( !Failed )
	{
		Executor->ProcessEvent( Function, Parms );

		for( TFieldIterator<UProperty> It(Function); It; ++It)
		{
			if ((It->PropertyFlags & CPF_ReturnParm)==CPF_ReturnParm)
			{
				BYTE* CurrentPropAddress = Parms + It->Offset;

				UProperty* Property = *It;
				
				ResultString = ExportProperty2(Function,*It,CurrentPropAddress);
			}			
		}
	}

	//!!destructframe see also UObject::ProcessEvent
	for( TFieldIterator<UProperty> It(Function); It && (It->PropertyFlags & (CPF_Parm|CPF_ReturnParm))==CPF_Parm; ++It )
	{
		It->DestroyValue( Parms + It->Offset );
	}

	// Success.
	delete ExecFunctionStack;
	return ResultString;
}
