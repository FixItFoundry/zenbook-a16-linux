// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2024, Qualcomm Innovation Center, Inc. All rights reserved.
 * Copyright (c) 2026, Reverse Engineered for X2-90
 */

#include <linux/clk-provider.h>
#include <linux/err.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>

#include "clk-alpha-pll.h"
#include "clk-branch.h"
#include "clk-pll.h"
#include "clk-rcg.h"
#include "clk-regmap.h"
#include "clk-regmap-divider.h"
#include "clk-regmap-mux.h"
#include "common.h"
#include "gdsc.h"
#include "reset.h"

/* 
 * TODO: Fill these in with the exact physical offsets extracted from qcpep8480.sys
 */
#define GPU_CC_CX_GMU_CLK_HALT_REG  0x5088
#define GPU_CC_GX_GMU_CLK_HALT_REG  0x5064
#define GPU_CC_GMU_BCR_REG          0x5000 /* Assumed */

#define GPUCC_GPU_CC_GMU_BCR 0
#define GPU_CC_CX_GMU_CLK 0
#define GPU_CC_GX_GMU_CLK 1

static const struct regmap_config gpu_cc_x2_regmap_config = {
	.reg_bits	= 32,
	.reg_stride	= 4,
	.val_bits	= 32,
	.max_register	= 0x9000,
	.fast_io	= true,
};

static struct clk_branch gpu_cc_cx_gmu_clk = {
	.halt_reg = GPU_CC_CX_GMU_CLK_HALT_REG,
	.halt_check = BRANCH_HALT,
	.clkr = {
		.enable_reg = GPU_CC_CX_GMU_CLK_HALT_REG,
		.enable_mask = BIT(0),
		.hw.init = &(const struct clk_init_data) {
			.name = "gpu_cc_cx_gmu_clk",
			.parent_hws = (const struct clk_hw*[]){
				/* TODO: Parent clock hw */
			},
			.num_parents = 1,
			.flags = CLK_SET_RATE_PARENT,
			.ops = &clk_branch2_ops,
		},
	},
};

static struct clk_branch gpu_cc_gx_gmu_clk = {
	.halt_reg = GPU_CC_GX_GMU_CLK_HALT_REG,
	.halt_check = BRANCH_HALT,
	.clkr = {
		.enable_reg = GPU_CC_GX_GMU_CLK_HALT_REG,
		.enable_mask = BIT(0),
		.hw.init = &(const struct clk_init_data) {
			.name = "gpu_cc_gx_gmu_clk",
			.parent_hws = (const struct clk_hw*[]){
				/* TODO: Parent clock hw */
			},
			.num_parents = 1,
			.flags = CLK_SET_RATE_PARENT,
			.ops = &clk_branch2_ops,
		},
	},
};

static const struct qcom_reset_map gpu_cc_x2_resets[] = {
	[GPUCC_GPU_CC_GMU_BCR] = { GPU_CC_GMU_BCR_REG },
};

static struct clk_regmap *gpu_cc_x2_clocks[] = {
	[GPU_CC_CX_GMU_CLK] = &gpu_cc_cx_gmu_clk.clkr,
	[GPU_CC_GX_GMU_CLK] = &gpu_cc_gx_gmu_clk.clkr,
};

static const struct qcom_cc_desc gpu_cc_x2_desc = {
	.config = &gpu_cc_x2_regmap_config,
	.clks = gpu_cc_x2_clocks,
	.num_clks = ARRAY_SIZE(gpu_cc_x2_clocks),
	.resets = gpu_cc_x2_resets,
	.num_resets = ARRAY_SIZE(gpu_cc_x2_resets),
};

static const struct of_device_id gpu_cc_x2_match_table[] = {
	{ .compatible = "qcom,x2-gpucc" },
	{ }
};
MODULE_DEVICE_TABLE(of, gpu_cc_x2_match_table);

static int gpu_cc_x2_probe(struct platform_device *pdev)
{
	struct regmap *regmap;
	
	regmap = qcom_cc_map(pdev, &gpu_cc_x2_desc);
	if (IS_ERR(regmap))
		return PTR_ERR(regmap);

	return qcom_cc_really_probe(&pdev->dev, &gpu_cc_x2_desc, regmap);
}

static struct platform_driver gpu_cc_x2_driver = {
	.probe = gpu_cc_x2_probe,
	.driver = {
		.name = "gpu_cc-x2",
		.of_match_table = gpu_cc_x2_match_table,
	},
};
module_platform_driver(gpu_cc_x2_driver);

MODULE_DESCRIPTION("QTI GPUCC X2-90 Driver");
MODULE_LICENSE("GPL v2");
