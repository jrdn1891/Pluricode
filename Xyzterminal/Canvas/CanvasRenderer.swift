import MetalKit
import simd

final class CanvasRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let nodePipeline: MTLRenderPipelineState
    let edgePipeline: MTLRenderPipelineState
    let document: CanvasDocument
    var terminalManager: TerminalManager?
    private(set) var theme = Theme(from: NSApp.effectiveAppearance)

    init(device: MTLDevice, document: CanvasDocument) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.document = document

        let library = device.makeDefaultLibrary()!

        let nodeDesc = MTLRenderPipelineDescriptor()
        nodeDesc.vertexFunction = library.makeFunction(name: "vertex_node")
        nodeDesc.fragmentFunction = library.makeFunction(name: "fragment_node")
        nodeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        nodeDesc.colorAttachments[0].isBlendingEnabled = true
        nodeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        nodeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        nodeDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        nodeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.nodePipeline = try! device.makeRenderPipelineState(descriptor: nodeDesc)

        let edgeVertexDesc = MTLVertexDescriptor()
        edgeVertexDesc.attributes[0].format = .float2
        edgeVertexDesc.attributes[0].offset = 0
        edgeVertexDesc.attributes[0].bufferIndex = 0
        edgeVertexDesc.attributes[1].format = .float4
        edgeVertexDesc.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        edgeVertexDesc.attributes[1].bufferIndex = 0
        edgeVertexDesc.layouts[0].stride = MemoryLayout<EdgeVertex>.stride

        let edgeDesc = MTLRenderPipelineDescriptor()
        edgeDesc.vertexFunction = library.makeFunction(name: "vertex_edge")
        edgeDesc.fragmentFunction = library.makeFunction(name: "fragment_edge")
        edgeDesc.vertexDescriptor = edgeVertexDesc
        edgeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        edgeDesc.colorAttachments[0].isBlendingEnabled = true
        edgeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        edgeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        edgeDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        edgeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.edgePipeline = try! device.makeRenderPipelineState(descriptor: edgeDesc)

        super.init()
    }

    func draw(in view: MTKView) {
        theme = Theme(from: NSApp.effectiveAppearance)
        view.clearColor = theme.canvasClearColor
        terminalManager?.sync(containerView: view)

        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor else { return }

        let viewportPoints = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        var uniforms = Uniforms(
            viewProjection: document.camera.viewProjectionMatrix(viewportSize: viewportPoints),
            viewportSize: viewportPoints,
            zoom: document.camera.zoom,
            contentsScale: Float(view.window?.backingScaleFactor ?? 2.0)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setCullMode(.none)

        let layouts = document.allSectionLayouts()
        drawEdges(encoder: encoder, uniforms: &uniforms, layouts: layouts)
        drawNodes(encoder: encoder, uniforms: &uniforms, layouts: layouts)
        drawMinimap(encoder: encoder, viewportPoints: viewportPoints, contentsScale: uniforms.contentsScale, layouts: layouts)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func drawEdges(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, layouts: [UUID: SectionLayout.Entry]) {
        var allVertices: [EdgeVertex] = []

        for edge in document.edges.values {
            guard let source = document.nodes[edge.sourceID],
                  let target = document.nodes[edge.targetID] else { continue }
            var color = colorForEdgeType(edge.edgeType)
            if document.selectedEdgeID == edge.id {
                color = SIMD4<Float>(0.5, 0.8, 1.0, 1.0)
            }
            let srcEntry = layouts[edge.sourceID]
            let tgtEntry = layouts[edge.targetID]
            allVertices.append(contentsOf: EdgeTessellator.tessellate(
                sourcePos: srcEntry?.position ?? source.position,
                sourceSize: srcEntry?.size ?? source.size,
                targetPos: tgtEntry?.position ?? target.position,
                targetSize: tgtEntry?.size ?? target.size,
                color: color
            ))
        }

        if let drag = document.edgeDrag,
           let source = document.nodes[drag.sourceNodeID] {
            let srcEntry = layouts[drag.sourceNodeID]
            allVertices.append(contentsOf: EdgeTessellator.tessellate(
                sourcePos: srcEntry?.position ?? source.position,
                sourceSize: srcEntry?.size ?? source.size,
                targetPos: drag.currentPoint - SIMD2<Float>(1, 1),
                targetSize: SIMD2<Float>(2, 2),
                color: SIMD4<Float>(0.5, 0.5, 0.6, 0.5)
            ))
        }

        guard !allVertices.isEmpty else { return }

        guard let buffer = device.makeBuffer(
            bytes: allVertices,
            length: MemoryLayout<EdgeVertex>.stride * allVertices.count,
            options: .storageModeShared
        ) else { return }

        encoder.setRenderPipelineState(edgePipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: allVertices.count)
    }

    private func drawNodes(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, layouts: [UUID: SectionLayout.Entry]) {
        var instances: [NodeInstance] = []

        for node in document.nodes.values {
            guard case .section(let sectionData) = node.kind else { continue }
            let isSelected = document.selectedNodeIDs.contains(node.id)
            let isHighlighted = document.highlightedSectionID == node.id && document.highlightedColumnIndex == nil
            let renderSize = sectionData.isCollapsed
                ? SIMD2<Float>(node.size.x, SectionLayout.headerHeight)
                : node.size
            instances.append(NodeInstance(
                position: node.position,
                size: renderSize,
                color: isHighlighted ? theme.sectionHighlightColor : theme.sectionNodeColor,
                cornerRadius: 12,
                selected: isSelected ? 1 : 0
            ))

            if sectionData.viewType == .kanban && !sectionData.isCollapsed {
                let statuses = TaskCardData.Status.allCases
                let numCols = Float(statuses.count)
                let colW = (node.size.x - SectionLayout.padding * 2 - SectionLayout.colGap * (numCols - 1)) / numCols

                if document.highlightedSectionID == node.id,
                   let colIdx = document.highlightedColumnIndex,
                   colIdx >= 0 && colIdx < statuses.count {
                    let colX = node.position.x + SectionLayout.padding + (colW + SectionLayout.colGap) * Float(colIdx)
                    instances.append(NodeInstance(
                        position: SIMD2<Float>(colX, node.position.y + SectionLayout.headerHeight),
                        size: SIMD2<Float>(colW, node.size.y - SectionLayout.headerHeight),
                        color: theme.sectionHighlightColor,
                        cornerRadius: 4,
                        selected: 0
                    ))
                }

                for i in 1..<statuses.count {
                    let x = node.position.x + SectionLayout.padding + (colW + SectionLayout.colGap) * Float(i) - SectionLayout.colGap * 0.5
                    instances.append(NodeInstance(
                        position: SIMD2<Float>(x - 0.5, node.position.y + SectionLayout.headerHeight),
                        size: SIMD2<Float>(1, node.size.y - SectionLayout.headerHeight - 8),
                        color: theme.sectionDividerColor,
                        cornerRadius: 0.5,
                        selected: 0
                    ))
                }
            }
        }

        for node in document.nodes.values {
            if case .section = node.kind { continue }
            let isSelected = document.selectedNodeIDs.contains(node.id)
            let entry = layouts[node.id]
            let color: SIMD4<Float> = switch node.kind {
            case .terminal(let data):
                if let pid = data.profileID, let profile = document.agentProfiles[pid] {
                    SIMD4(profile.color.x * 0.25, profile.color.y * 0.25, profile.color.z * 0.25, 1.0)
                } else {
                    theme.terminalNodeColor
                }
            case .taskCard: theme.taskCardNodeColor
            case .section: theme.sectionNodeColor
            }
            instances.append(NodeInstance(
                position: entry?.position ?? node.position,
                size: entry?.size ?? node.size,
                color: color,
                cornerRadius: 8,
                selected: isSelected ? 1 : 0
            ))
        }

        if let rect = document.selectionRect {
            instances.append(NodeInstance(
                position: SIMD2<Float>(
                    min(rect.origin.x, rect.origin.x + rect.size.x),
                    min(rect.origin.y, rect.origin.y + rect.size.y)
                ),
                size: SIMD2<Float>(abs(rect.size.x), abs(rect.size.y)),
                color: SIMD4<Float>(0.3, 0.5, 1.0, 0.12),
                cornerRadius: 2,
                selected: 0
            ))
        }

        guard !instances.isEmpty else { return }
        guard let buffer = device.makeBuffer(
            bytes: instances,
            length: MemoryLayout<NodeInstance>.stride * instances.count,
            options: .storageModeShared
        ) else { return }

        encoder.setRenderPipelineState(nodePipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)
    }

    private func colorForEdgeType(_ type: EdgeType) -> SIMD4<Float> {
        switch type {
        case .handsOffTo: return SIMD4<Float>(0.4, 0.7, 0.4, 0.8)
        case .reviews: return SIMD4<Float>(0.7, 0.5, 0.2, 0.8)
        case .assignedTo: return SIMD4<Float>(0.35, 0.55, 1.0, 0.8)
        case .blocks, .blockedBy: return SIMD4<Float>(0.7, 0.3, 0.3, 0.8)
        case .flowsTo: return SIMD4<Float>(0.5, 0.4, 0.9, 0.8)
        }
    }

    private func drawMinimap(encoder: MTLRenderCommandEncoder, viewportPoints: SIMD2<Float>, contentsScale: Float, layouts: [UUID: SectionLayout.Entry]) {
        guard !document.minimapCollapsed else { return }

        let nodes = Array(document.nodes.values)
        guard !nodes.isEmpty else { return }

        var minP = SIMD2<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxP = SIMD2<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        for node in nodes {
            let pos = layouts[node.id]?.position ?? node.position
            let size = layouts[node.id]?.size ?? node.size
            minP = simd_min(minP, pos)
            maxP = simd_max(maxP, pos + size)
        }

        let padding: Float = 200
        minP -= SIMD2<Float>(padding, padding)
        maxP += SIMD2<Float>(padding, padding)
        let worldSize = maxP - minP
        guard worldSize.x > 0 && worldSize.y > 0 else { return }

        let mapW: Float = 160
        let mapH = mapW * (worldSize.y / worldSize.x)
        let mapMargin: Float = 12
        let mapX = viewportPoints.x - mapW - mapMargin
        let mapY = viewportPoints.y - mapH - mapMargin

        let mapScale = mapW / worldSize.x

        var instances: [NodeInstance] = []

        instances.append(NodeInstance(
            position: SIMD2<Float>(mapX, mapY),
            size: SIMD2<Float>(mapW, mapH),
            color: theme.minimapBackground,
            cornerRadius: 6,
            selected: 0
        ))

        for node in nodes {
            let pos = layouts[node.id]?.position ?? node.position
            let size = layouts[node.id]?.size ?? node.size
            let rel = (pos - minP) * mapScale
            let sz = size * mapScale
            let color: SIMD4<Float> = switch node.kind {
            case .terminal: SIMD4<Float>(0.3, 0.8, 0.3, 0.9)
            case .taskCard: SIMD4<Float>(0.5, 0.5, 0.65, 0.9)
            case .section: SIMD4<Float>(0.4, 0.4, 0.55, 0.5)
            }
            instances.append(NodeInstance(
                position: SIMD2<Float>(mapX + rel.x, mapY + rel.y),
                size: SIMD2<Float>(max(3, sz.x), max(2, sz.y)),
                color: color,
                cornerRadius: 1,
                selected: 0
            ))
        }

        let cam = document.camera
        let vpCanvasW = viewportPoints.x / cam.zoom
        let vpCanvasH = viewportPoints.y / cam.zoom
        let vpTopLeft = SIMD2<Float>(cam.offset.x - vpCanvasW * 0.5, cam.offset.y - vpCanvasH * 0.5)
        let vpRel = (vpTopLeft - minP) * mapScale
        let vpSz = SIMD2<Float>(vpCanvasW, vpCanvasH) * mapScale

        let clampedX = max(mapX, min(mapX + vpRel.x, mapX + mapW - 4))
        let clampedY = max(mapY, min(mapY + vpRel.y, mapY + mapH - 4))
        let clampedW = min(max(4, vpSz.x), mapX + mapW - clampedX)
        let clampedH = min(max(4, vpSz.y), mapY + mapH - clampedY)

        instances.append(NodeInstance(
            position: SIMD2<Float>(clampedX, clampedY),
            size: SIMD2<Float>(clampedW, clampedH),
            color: theme.minimapViewportFrame,
            cornerRadius: 2,
            selected: 0
        ))

        guard let buffer = device.makeBuffer(
            bytes: instances,
            length: MemoryLayout<NodeInstance>.stride * instances.count,
            options: .storageModeShared
        ) else { return }

        let sx: Float = 2.0 / viewportPoints.x
        let sy: Float = -2.0 / viewportPoints.y
        var mapUniforms = Uniforms(
            viewProjection: simd_float4x4(
                SIMD4<Float>(sx, 0, 0, 0),
                SIMD4<Float>(0, sy, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(-1, 1, 0, 1)
            ),
            viewportSize: viewportPoints,
            zoom: 1,
            contentsScale: contentsScale
        )

        encoder.setRenderPipelineState(nodePipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&mapUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)
    }
}
