//
//  SetEntityClasses.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.06.26.
//

import CoreData

// Class shells for the concrete set entities, whose codegen is set to Category/Extension:
// Xcode still generates their attribute accessors and typed fetch requests, but the class
// declarations live here. With full class codegen, the generated class files for entities
// that have a parent entity never reference CoreData in a public declaration, so every
// build emits "public import of 'CoreData' was not used" warnings that cannot be fixed in
// generated code.

@objc(DropSet)
public class DropSet: WorkoutSet {}

@objc(StandardSet)
public class StandardSet: WorkoutSet {}

@objc(SuperSet)
public class SuperSet: WorkoutSet {}

@objc(TemplateDropSet)
public class TemplateDropSet: TemplateSet {}

@objc(TemplateStandardSet)
public class TemplateStandardSet: TemplateSet {}

@objc(TemplateSuperSet)
public class TemplateSuperSet: TemplateSet {}
