// SPDX-License-Identifier: GPL-2.0
/*
 * soccp_glink - stand-alone registrar for the SOCCP GLINK-over-SMEM edge on
 * the ASUS Zenbook A16 (Snapdragon X2 Elite "Glymur").
 *
 * Background (test41 RE): the battery/charger service on this platform is
 * PMIC-GLINK hosted on the SOCCP (SoC Companion Processor), glink channel
 * "PMIC_RTR_SOCCP_APPS" (proven from qcpmicglink8480.sys). The in-tree
 * pmic_glink driver already matches that channel (pmic_glink.c:285), but
 * nothing in this kernel registers a SOCCP glink edge (remoteproc/ has no
 * soccp support), so the channel never appears and qcom_battmgr stays empty.
 *
 * The SOCCP is UEFI-loaded and already running (smp2p-soccp negotiated), so we
 * do NOT need remoteproc/PAS - we only need to stand up the SMEM glink
 * transport for its host-pid. qcom_glink_smem_register() is exported and does
 * exactly that from a DT node describing the edge (qcom,remote-pid + mboxes +
 * interrupts). This module binds an inert DT wrapper node "asus,soccp-glink"
 * and registers its "glink-edge" child. Reversible: rmmod unregisters it.
 *
 * RESULT (test42, 2026-07-11): loading this against test37 DTB brought up
 * PMIC_RTR_SOCCP_APPS + PMIC_LOGS_SOCCP_APPS; pmic_glink bound; qcom-battmgr-bat
 * went live (12.66 V, 30.7 C, cycle 14, ASUS mfr; upower 79.56%, 70.088 Wh).
 * First working battery on the A16 via the upstream battmgr path.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/err.h>

/* opaque; real definition lives in drivers/rpmsg/qcom_glink_smem.c */
struct qcom_glink_smem;
extern struct qcom_glink_smem *qcom_glink_smem_register(struct device *parent,
							struct device_node *node);
extern void qcom_glink_smem_unregister(struct qcom_glink_smem *smem);

struct soccp_glink {
	struct qcom_glink_smem *edge;
	struct device_node *edge_node;
};

static int soccp_glink_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct soccp_glink *sg;
	struct device_node *edge_node;
	struct qcom_glink_smem *edge;
	u32 rpid = 0;

	sg = devm_kzalloc(dev, sizeof(*sg), GFP_KERNEL);
	if (!sg)
		return -ENOMEM;

	edge_node = of_get_child_by_name(dev->of_node, "glink-edge");
	if (!edge_node) {
		dev_err(dev, "no glink-edge child node\n");
		return -ENODEV;
	}
	of_property_read_u32(edge_node, "qcom,remote-pid", &rpid);

	edge = qcom_glink_smem_register(dev, edge_node);
	if (IS_ERR(edge)) {
		dev_err(dev, "qcom_glink_smem_register(remote-pid=%u) failed: %ld\n",
			rpid, PTR_ERR(edge));
		of_node_put(edge_node);
		return PTR_ERR(edge);
	}

	sg->edge = edge;
	sg->edge_node = edge_node;
	platform_set_drvdata(pdev, sg);
	dev_info(dev, "SOCCP glink edge registered (remote-pid=%u)\n", rpid);
	return 0;
}

static void soccp_glink_remove(struct platform_device *pdev)
{
	struct soccp_glink *sg = platform_get_drvdata(pdev);

	if (sg && sg->edge)
		qcom_glink_smem_unregister(sg->edge);
	if (sg)
		of_node_put(sg->edge_node);
}

static const struct of_device_id soccp_glink_of_match[] = {
	{ .compatible = "asus,soccp-glink" },
	{}
};
MODULE_DEVICE_TABLE(of, soccp_glink_of_match);

static struct platform_driver soccp_glink_driver = {
	.probe = soccp_glink_probe,
	.remove = soccp_glink_remove,
	.driver = {
		.name = "soccp_glink",
		.of_match_table = soccp_glink_of_match,
	},
};
module_platform_driver(soccp_glink_driver);

MODULE_DESCRIPTION("SOCCP GLINK-over-SMEM edge registrar (A16 battery bring-up)");
MODULE_LICENSE("GPL");
