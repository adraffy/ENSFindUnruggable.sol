import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { dnsEncode } from "ethers";
import { type DeployedContract, Foundry } from "@adraffy/blocksmith";

describe("ENSFindUnruggable", () => {
	let foundry: Foundry;
	let finder: DeployedContract;
	beforeAll(async () => {
		foundry = await Foundry.launch({
			fork: "https://mainnet.gateway.tenderly.co",
			infoLog: false,
		});
		afterAll(foundry.shutdown);
		finder = await foundry.deploy({
			file: "ENSFindUnruggable",
			args: ["0xED73a03F19e8D849E44a39252d222c6ad5217E1e"],
		});
	});

	it("raffy.teamnick.eth", async () => {
		const [verifier, gateways] = await finder.findUnruggable(
			dnsEncode("raffy.teamnick.eth")
		);
		expect(verifier, "verifier").toStrictEqual(
			"0x82304C5f4A08cfA38542664C5B78e1969cA49Cec"
		);
		expect([...gateways], "gateways").toStrictEqual([
			"https://lb.drpc.org/gateway/unruggable?network=base",
		]);
	});

	it("raffy primary", async () => {
		const [verifier, gateways] = await finder.findUnruggable(
			dnsEncode("51050ec063d393217b436747617ad1c2285aeeee.80002105.reverse")
		);
		expect(verifier, "verifier").toStrictEqual(
			"0x074C93CD956B0Dd2cAc0f9F11dDA4d3893a88149"
		);
		expect([...gateways], "gateways").toStrictEqual([
			"https://lb.drpc.org/gateway/unruggable?network=base",
			"https://base.3668.io"
		]);
	});
});
