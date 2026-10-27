//
//  ExcalidrawElement+Inits.swift
//  ExcalidrawZ
//
//  Memberwise-style initialisers for elements the app builds itself
//  (Lessonspace import). The structs declare init(from:), which hides
//  the synthesized memberwise init.
//

import Foundation

extension ExcalidrawArrowElement {
    init(
        id: String,
        x: Double,
        y: Double,
        strokeColor: String,
        backgroundColor: String,
        fillStyle: ExcalidrawFillStyle,
        strokeWidth: Double,
        strokeStyle: ExcalidrawStrokeStyle,
        roundness: ExcalidrawRoundness?,
        roughness: Double,
        opacity: Double,
        width: Double,
        height: Double,
        angle: Double,
        seed: Int,
        version: Int,
        versionNonce: Int,
        index: String?,
        isDeleted: Bool,
        groupIds: [String],
        frameId: String?,
        boundElements: [ExcalidrawBoundElement]?,
        updated: Double?,
        link: String?,
        locked: Bool?,
        customData: [String: AnyCodable]?,
        type: ExcalidrawElementType,
        points: [Point],
        lastCommittedPoint: Point?,
        startBinding: PointBinding?,
        endBinding: PointBinding?,
        startArrowhead: Arrowhead?,
        endArrowhead: Arrowhead?,
        elbowed: Bool,
        fixedSegments: [FixedSegment]?,
        startIsSpecial: Bool?,
        endIsSpecial: Bool?
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.strokeColor = strokeColor
        self.backgroundColor = backgroundColor
        self.fillStyle = fillStyle
        self.strokeWidth = strokeWidth
        self.strokeStyle = strokeStyle
        self.roundness = roundness
        self.roughness = roughness
        self.opacity = opacity
        self.width = width
        self.height = height
        self.angle = angle
        self.seed = seed
        self.version = version
        self.versionNonce = versionNonce
        self.index = index
        self.isDeleted = isDeleted
        self.groupIds = groupIds
        self.frameId = frameId
        self.boundElements = boundElements
        self.updated = updated
        self.link = link
        self.locked = locked
        self.customData = customData
        self.type = type
        self.points = points
        self.lastCommittedPoint = lastCommittedPoint
        self.startBinding = startBinding
        self.endBinding = endBinding
        self.startArrowhead = startArrowhead
        self.endArrowhead = endArrowhead
        self.elbowed = elbowed
        self.fixedSegments = fixedSegments
        self.startIsSpecial = startIsSpecial
        self.endIsSpecial = endIsSpecial
    }
}

extension ExcalidrawTextElement {
    init(
        type: ExcalidrawElementType,
        id: String,
        x: Double,
        y: Double,
        strokeColor: String,
        backgroundColor: String,
        fillStyle: ExcalidrawFillStyle,
        strokeWidth: Double,
        strokeStyle: ExcalidrawStrokeStyle,
        roundness: ExcalidrawRoundness?,
        roughness: Double,
        opacity: Double,
        width: Double,
        height: Double,
        angle: Double,
        seed: Int,
        version: Int,
        versionNonce: Int,
        index: String?,
        isDeleted: Bool,
        groupIds: [String],
        frameId: String?,
        boundElements: [ExcalidrawBoundElement]?,
        updated: Double?,
        link: String?,
        locked: Bool?,
        customData: [String: AnyCodable]?,
        fontSize: Double,
        fontFamily: FontFamily,
        text: String,
        textAlign: TextAlign,
        verticalAlign: VerticalAlign,
        containerId: ExcalidrawGenericElement.ID?,
        originalText: String?,
        autoResize: Bool,
        lineHeight: Double?
    ) {
        self.type = type
        self.id = id
        self.x = x
        self.y = y
        self.strokeColor = strokeColor
        self.backgroundColor = backgroundColor
        self.fillStyle = fillStyle
        self.strokeWidth = strokeWidth
        self.strokeStyle = strokeStyle
        self.roundness = roundness
        self.roughness = roughness
        self.opacity = opacity
        self.width = width
        self.height = height
        self.angle = angle
        self.seed = seed
        self.version = version
        self.versionNonce = versionNonce
        self.index = index
        self.isDeleted = isDeleted
        self.groupIds = groupIds
        self.frameId = frameId
        self.boundElements = boundElements
        self.updated = updated
        self.link = link
        self.locked = locked
        self.customData = customData
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.text = text
        self.textAlign = textAlign
        self.verticalAlign = verticalAlign
        self.containerId = containerId
        self.originalText = originalText
        self.autoResize = autoResize
        self.lineHeight = lineHeight
    }
}
