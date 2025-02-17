// Copyright 2022 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef IREE_COMPILER_CODEGEN_COMMON_TRANSFORMEXTENSIONS_COMMONEXTENSIONS
#define IREE_COMPILER_CODEGEN_COMMON_TRANSFORMEXTENSIONS_COMMONEXTENSIONS

include "mlir/Dialect/PDL/IR/PDLTypes.td"
include "mlir/Dialect/Transform/IR/TransformAttrs.td"
include "mlir/Dialect/Transform/IR/TransformDialect.td"
include "mlir/Dialect/Transform/IR/TransformInterfaces.td"
include "mlir/Dialect/Transform/IR/TransformTypes.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Dialect/SCF/IR/DeviceMappingInterface.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/OpBase.td"

def ApplyBufferOptimizationsOp :
  Op<Transform_Dialect, "iree.apply_buffer_optimizations",
    [TransformEachOpTrait,
     TransformOpInterface,
     DeclareOpInterfaceMethods<MemoryEffectsOpInterface>]> {
  let description = [{
    This applies memory optimization on memref. In particular it does store to
    load forwarding, dead store elimination and dead alloc elimination.

    #### Return modes

    This operation applies a set of memory optimization on the whole region of
    the operand.

    The transformation does not consume the target handle.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target);
  let results = (outs);

  let assemblyFormat = "$target attr-dict `:` functional-type($target, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";

  let skipDefaultBuilders = 1;
  let builders = [
    OpBuilder<(ins "Value":$target)>
  ];
  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::Operation *target,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def ApplyPatternsOp : Op<Transform_Dialect, "iree.apply_patterns",
    [DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
     TransformEachOpTrait,
     TransformOpInterface]> {
  let description = [{
    Greedily applies patterns as specified by its attributes.

    Must be applied to an op with trait IsolatedFromAbove since the
    GreedyPatternRewriter asserts those. Internally, uses the tracking rewriter
    to preserve handles to payload operations nested within operations
    associated with `target`. Fails if tracking cannot find replacement for a
    payload operation. This may become controllable with an attribute in the
    future.

    Returns the IsolatedFromAbove op whose content it has modified for better
    chaining APIs.

    The following additive attributes can be set, they add patterns in an
    unspecified order:
      - additional_iree_patterns: fancy patterns we shortcut into the system,
      will need to be sliced out better in the future.
      - bubble_collapse: bubble `collapse_shape` down across Linalg ops. This
      must be applied separately from `bubble_expand` patterns because of some
      upstream pattern interference issue atm.
      - bubble_expand: bubble `expand_shape` down across Linalg ops. This
      must be applied separately from `bubble_collapse` patterns because of some
      upstream pattern interference issue atm.
      - bubble_pack_un_pack: bubble `pack` up and `unpack` down across Linalg
      ops.
      - canonicalization: adds all the canonicalization patterns of all
      registered dialects and ops.
      - cse: additionally apply common subexpression elimination. This must
      apply on a funcOp. This is not a set of patterns per se but is still very
      convenient to apply it close to canonicalization and other greedy pattern
      applications.
      - erase_unnecessary_tensor_operands: add patterns that erase unnecessary
      tensor operands.
      - expand_memref_strided_metadata: adds patterns that expand memref
      operations into extract_strided_metadata operations and a materialization
      of their effect on the metadata (sizes, offset, strides).
      - extract_address_computations: adds patterns for anchoring subview 
      accessing operations at [0, ... 0].
      - fold_memref_aliases: adds patterns for folding ops such as
      memref.subview.
      - fold_reassociative_reshapes: adds patterns that fold insert_slice/
      extract_slice ops with reassociative reshape ops.
      - fold_tensor_empty_extract: Fold tensor.empty used by extract_slice in
      case it is the only use of extract.
      - fold_tensor_subsets: adds patterns for folding tensor subset ops into
      their producer and consumers.
      - licm: additionally apply loop-independent code motion and single 
      iteration loop promotion. This is not a set of patterns per se but is still
      very convenient to apply it close to canonicalization and other greedy
      pattern applications.
      - linalg_elementwise_greedy_fusion: add linalg elementwise ops fusion
      patterns using a naive default heuristic.
      - lower_transfer_op_permutations: Lower transfer ops to transfer ops
      with minor identity permutations.
      - lower_vector_masks: Lower vector.mask ops away.
      - prepare_vector_to_mma: pre-process vector.contract op to set it in a form
      that can be mapped to nvgpu.mma operations. 
      - rank_reducing_linalg: adds patterns that results in rank-reducing
      behavior on subset-based linalg operations using insert/extract slices.
      - rank_reducing_linalg_via_reshapes: adds patterns that results in rank-reducing
      behavior on subset-based linalg operations using expand/collapse shape ops.
      - rank_reducing_vector: adds patterns that results in rank-reducing
      behavior on subset-based vector operations.
      adopts the upstream version.
      - swapping_patterns: adds patterns that swap operations for a better outcome.
      This is a catch all that can be refined further if/when needed.
      - swap_padding_elide_conditional: refines the tensor.pad +
      tensor.extract_slice swapping pattern. This injects static information
      that guarantees padding is smaller than the window size which guarantees
      we never see a tile comprised of padding-only.
      - tiling_canonicalization: adds specific tiling-related canonicalization
      patterns.
      - unroll_vectors_gpu_mma_sync: adds patterns that unroll vectors to a native tile
      size for GPUs with mma operations. The size is currently hardcoded but
      should be refactored upstream and made pluggable.
      - unroll_vectors_gpu_wmma: adds patterns that unroll vectors to a native tile
      size for GPUs with wmma operations. The size is currently hardcoded but
      should be refactored upstream and made pluggable.


    #### Return modes:

    This operation applies a set of patterns specified by attributes. To apply
    these patterns, this operation must target an operation that is isolated
    from above, otherwise the transform definitely fails.

    If the pattern application fails, or if the underlying listener fails to
    capture op handles, the transformation definitely fails.

    Otherwise the transformation is successful.

    This operation does not consume the target handle and does not produce any
    handle.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target,
                       UnitAttr:$additional_iree_patterns,
                       UnitAttr:$bubble_collapse,
                       UnitAttr:$bubble_expand,
                       UnitAttr:$bubble_pack_un_pack,
                       UnitAttr:$canonicalization,
                       UnitAttr:$cse,
                       UnitAttr:$erase_unnecessary_tensor_operands,
                       UnitAttr:$expand_memref_strided_metadata,
                       UnitAttr:$extract_address_computations,
                       UnitAttr:$fold_memref_aliases,
                       UnitAttr:$fold_reassociative_reshapes,
                       UnitAttr:$fold_tensor_empty_extract,
                       UnitAttr:$fold_tensor_subsets,
                       UnitAttr:$licm,
                       UnitAttr:$linalg_elementwise_greedy_fusion,
                       UnitAttr:$lower_transfer_op_permutations,
                       UnitAttr:$lower_vector_masks,
                       UnitAttr:$prepare_vector_to_mma,
                       UnitAttr:$rank_reducing_linalg,
                       UnitAttr:$rank_reducing_linalg_via_reshapes,
                       UnitAttr:$rank_reducing_vector,
                       UnitAttr:$swap_padding_elide_conditional,
                       UnitAttr:$swapping_patterns,
                       UnitAttr:$tiling_canonicalization,
                       UnitAttr:$unroll_vectors_gpu_mma_sync,
                       UnitAttr:$unroll_vectors_gpu_wmma);
  let results = (outs);

  let assemblyFormat = "$target attr-dict `:` functional-type($target, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";

  let builders = [
    // TODO: Some bitvector to scale better than n-bools.
    OpBuilder<(ins "Value":$target,
                   "const ApplyPatternsOpPatterns &":$patterns)>
  ];

  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::Operation *target,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def HoistStaticAllocOp :  Op<Transform_Dialect, "iree.hoist_static_alloc",
    [DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
     TransformEachOpTrait,
     TransformOpInterface]> {
  let summary = "Hoist static allocations";
  let description = [{
    Find static allocations and hoist them to the top level.

    #### Return modes
    This transform applies static alloc hoisting the whole region of the operand.

    It does not consume the target handle and always return success.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target);
  let results = (outs);

  let assemblyFormat = "$target attr-dict `:` functional-type(operands, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";

  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::func::FuncOp funcOp,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def IREEBufferizeOp : Op<Transform_Dialect, "iree.bufferize",
    [FunctionalStyleTransformOpTrait,
     MemoryEffectsOpInterface,
     DeclareOpInterfaceMethods<TransformOpInterface>]> {
  let description = [{
    Target the whole hal.executable_variant op and call upstream comprehensive
    bufferize with extra IREE hooks.

    By default, CPU allocations are emitted. This behavior can be modified by
    using the following attributes:
      - target_gpu: if set, GPU allocations are emitted.

    #### Return modes

    This operation calls the upstream one-shot bufferization pass with extra
    registered patterns for IREE.

    The pass is ran on all the ModuleOp nested under the top-level op on which
    the transform dialect interpreter pass is applied.

    If any of the pass on any of the ModuleOp fails, the transformation
    definitely fails. Otherwise the transformation succeeds.

    This transform consumes the target handle and produces a result handle.
  }];

  let arguments = (
      ins TransformHandleTypeInterface:$target,
          UnitAttr:$target_gpu,
          UnitAttr:$test_analysis_only,
          UnitAttr:$print_conflicts
  );
  let results = (outs TransformHandleTypeInterface:$result);

  let assemblyFormat = "attr-dict $target `:` functional-type($target, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";

  let builders = [
    OpBuilder<(ins "Value":$target,
                   CArg<"bool", "false">:$targetGpu,
                   CArg<"bool", "false">:$testAnalysisOnly,
                   CArg<"bool", "false">:$printConflicts)>
  ];
}

def IREEEliminateEmptyTensorsOp : Op<
    Transform_Dialect, "iree.eliminate_empty_tensors",
    [DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
     TransformEachOpTrait,
     TransformOpInterface]> {
  let description = [{
    This is a pre-processing pass for iree.bufferize. It tries to remove
    tensor.empty ops by replacing them with suitable destination tensors,
    which can reduce the number of allocations when bufferizing.

    This transform is not part of iree.bufferize because additional
    canonicalization are sometimes possible after eliminate_empty_tensors but
    before iree.bufferize.

    #### Return modes

    This transform does not consume the target handle and always return success.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target);
  let results = (outs);
  let assemblyFormat = "attr-dict $target `:` functional-type($target, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";
  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::Operation *target,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def IREEEraseHALDescriptorTypeFromMemRefOp : Op<Transform_Dialect,
    "iree.erase_hal_descriptor_type_from_memref",
    [DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
     TransformEachOpTrait,
     TransformOpInterface]> {
  let description = [{
    Erase #hal.descriptor_type from MemRef memory space to ignore all IREE
    memory space planning. This is meant to ease transitioning given that
    various LLVM conversion upstream patterns assumes numeric memory space,
    especially the default 0.

    Return modes:
    =============
    The pass is ran on all FuncOp nested under the top-level op on which
    the transform dialect interpreter pass is applied.

    If any of the pass on any of the FuncOp fails, the transformation
    definitely fails. Otherwise the transformation succeeds.

    This transform does not consume the target handle.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target);
  let results = (outs);

  let assemblyFormat = "attr-dict $target `:` functional-type($target, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";
  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::Operation *target,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def ForallToWorkgroupOp : Op<Transform_Dialect,
    "iree.forall_to_workgroup",
    [DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
     TransformEachOpTrait,
     TransformOpInterface]> {
  let description = [{
    Target the whole hal.executable_variant op and rewrite the unique topLevel
    scf.forall to distributed workgroup_id and workgroup_count.

    The mapping of threads to workgroup_id is currently one-to-one and in order.
    Only **bufferized** scf.forall are currently supported.
    Only scf.forall distributed to **at most 3 dimensions** are currently
    supported.

    Return modes:
    =============
    This operation ignores non-Func ops and drops them in the return.

    If no unique scf.forall topLevel operation is found, then the
    transform definitely fails.
    If the unique topLevel scf.forall has results (i.e. tensors), then
    the transform definitely fails.

    If the unique topLevel scf.forall maps to a dynamic number of
    threads, then the transform definitely fails. This is a temporary
    limitation until the backward slice computing scf.forall.num_threads
    can be extracted into the hal::executable_export workgroup_count region.
    This region may require arbitrary computations and cannot magically match
    what the `stream.cmd.dispatch` has already imposed on us at a distance.
    For now we must specify the number of values properly when applying the
    topLevel tile_to_forall_op.

    If the unique topLevel scf.forall operation contained within the
    FuncOp referred to by the `target` transform handle lowers to workgroup
    properly, the transform succeeds.

    Otherwise the transform definitely fails.

    This transform does not consume its input handle and produces no result.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target);
  let results = (outs);

  let assemblyFormat = "$target attr-dict `:` functional-type($target, results)";
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";

  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::func::FuncOp target,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def ShareForallOperandsOp : Op<
    Transform_Dialect, "iree.share_forall_operands", [
      FunctionalStyleTransformOpTrait,
      MemoryEffectsOpInterface,
      TransformEachOpTrait,
      TransformOpInterface]> {
  let description = [{
    Target a single scf.forall op and shares all uses of the specified
    `share_operands` operand indices.

    Sharing can be thought of as the inverse of traditional privatization.
    Privatization consists in determining that a part of memory is only accessed
    by a single thread to and subsequently slicing out that part into a
    thread_private storage that has smaller footprint, better locality and better
    alignment properties.
    In the case of scf.forall on tensors, tensor values are immutable
    and the same tensor value may be passed as `shared_outs` and also captured
    for internal uses.
    Due to the immutability property, the whole tensor values are private by
    construction and result in alloc + copy of the whole tensor on every thread
    to maintain the original SSA value after bufferizing.

    An analysis similar to privatization is needed to ensure that only a private
    slice is needed and that the whole tensor can be shared.
    This transformation amounts to injecting the result of such an analysis as
    static information in the program.
    The transformation checks that the values captured are `tensor.extract_slice`
    with a matching `tensor.parallel_insert_slice`, to approximate the lack of
    a cross-thread dependence analysis.
    However this can still be unsafe wrt parallelism so use carefully!

    Sharing consists in rewriting all uses of the operands passed as
    `shared_outs` that are also captured wihtin the `scf.forall` region
    into the matching `shared_outs` bbarg.

    Only those operands whose indices are specified in `share_operands` are
    shared. An empty `share_operands` specification considers all operands to
    be shared.

    #### Return modes

    If any of the `share_operands` indices overflow, a definite error is produced.

    If a `share_operands` fails a sharing precondition, it is ignored.
    In the future, we should emit a notification.

    This transform consumes the target handle and produces a result handle to
    the modified `scf.forall` op.
  }];

  let arguments = (
      ins TransformHandleTypeInterface:$forall_op,
          DefaultValuedOptionalAttr<DenseI64ArrayAttr, "{}">:$share_operands
  );
  let results = (outs TransformHandleTypeInterface:$result);

  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";

  let assemblyFormat = [{
    $forall_op (`share_operands` `=` $share_operands^ )? attr-dict
      `:` functional-type(operands, results)
  }];

  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::scf::ForallOp forallOp,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def IREEPopulateWorkgroupCountRegionUsingNumThreadsSliceOp :
    Op<Transform_Dialect, "iree.populate_workgroup_count_region_using_num_threads_slice",
      [DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
       TransformEachOpTrait,
       TransformOpInterface]> {
  let description = [{
    Populate the workgroup_count region on the `hal.executable.export` op.

    The default dispatch region formation expects that the workgroup count
    be computed from within the dispatch by using a program slice. The utility
    method `lowerWorkgroupCountFromSliceOp` handles populating the
    workgroup count region given the values in the dispatch that represent the
    number of workgroups. This transform op calls the underlying function using
    the `num_threads` value from the `scf.for_all` op that distributes the work
    to different workgroups.
  }];

  let arguments = (ins PDL_Operation:$for_all_op);
  let results = (outs);
  let assemblyFormat = [{
    attr-dict $for_all_op `:` functional-type($for_all_op, results)
  }];
  let cppNamespace = "mlir::iree_compiler::IREE::transform_dialect";
  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
      ::mlir::Operation *target,
      ::mlir::transform::ApplyToEachResultList &results,
      ::mlir::transform::TransformState &state);
  }];
}

#endif // IREE_COMPILER_CODEGEN_COMMON_TRANSFORMEXTENSIONS_COMMONEXTENSIONS
