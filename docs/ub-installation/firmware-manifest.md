# 固件包清单

整机（UB）固件与软件包**不在本仓库**：按 2026-11-26 的决定已拆为独立包，本文件是文档与固件之间的唯一凭据。

- 文件数：**111**
- 解包后总大小：**231.4 MiB**
- 其中 **77** 个在原仓库以 Git LFS 指针提交，下表列出的是指针记录的真实大小与 sha256，拿到实体文件后可直接校验。
- 校验文件：`firmware.sha256`（与固件包同目录，`sha256sum -c firmware.sha256`）
- 获取方式见 [`firmware-README.md`](firmware-README.md)。

| 路径 | 大小 | SHA-256 | 类型 |
|---|---|---|---|
| `包/B006/BeiMing/HCOM/ubs-comm-devel-1.0.1-10.oe2403sp4.aarch64.rpm` | 2,199,077 B | `9bd968b2a951d456e1df221030639ac33e2a412aa56fb4bb0da7d359b24b01e6` | LFS 指针 |
| `包/B006/BeiMing/HCOM/ubs-comm-lib-1.0.1-10.oe2403sp4.aarch64.rpm` | 1,390,845 B | `9adad9442ef5fe4bc9138c37eb300b19f933ddec3fff6a7f96caef11e1dd2c85` | LFS 指针 |
| `包/B006/BeiMing/OpenStackPlugin/ubs-openstack-python3.11-1.0-1.aarch64.rpm` | 131,809 B | `4a803b3ce8c20ca6f7581a063e5fbc37f97db6584323945f1826b38cafd45e25` | LFS 指针 |
| `包/B006/BeiMing/UBSE/python3-ubs-engine-1.0.1-22.oe2403sp4.noarch.rpm` | 117,781 B | `0147aab14fe7b37274ba3c5af878609e2854227b56c7ecb3f64b66f031174924` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-1.0.1-22.oe2403sp4.aarch64.rpm` | 2,953,517 B | `b61b235bb86599695b86b99c6805d52802dcf7065463886c2a1a31c13115ebcf` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-client-devel-1.0.1-22.oe2403sp4.aarch64.rpm` | 102,253 B | `9d581a573effce49ac18b34500042f7a23ef33de61026a413ff5461acf7a22bc` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-client-libs-1.0.1-22.oe2403sp4.aarch64.rpm` | 96,873 B | `b156a97e95aee4bc0180276585cf03bfe489792ca0cc0123fedb30169cfce0f5` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-processmem-1.0.1-22.oe2403sp4.aarch64.rpm` | 96,229 B | `cec4f12e0747d1babca0c76b934b4db0b9f790cf6198b8cbc11a0cfa0091f848` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-rmrs-1.0.1-22.oe2403sp4.aarch64.rpm` | 847,425 B | `59e8f89108e565c675676d240e387524067a560cd6d2b18fac0df9545e00ec7b` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-ucache-1.0.1-22.oe2403sp4.aarch64.rpm` | 200,537 B | `e2f087518ebb37cce99a730f5efd67e16d2e77e4399f1fbb0c965f742cef1afe` | LFS 指针 |
| `包/B006/BeiMing/UBSE/ubs-engine-virtagent-1.0.1-22.oe2403sp4.aarch64.rpm` | 556,469 B | `6bf83d07d464d6a791367a47532ccc24182a35ca7a6b76ac8460de8ba6e606d2` | LFS 指针 |
| `包/B006/BeiMing/UBSM/ubs-mem-1.0.1-1.oe2403sp4.aarch64.rpm` | 3,381 B | `a26a848aac8ba1451705ba80da5d6bb9aee69657d7b6c11817e98e74897a224a` | LFS 指针 |
| `包/B006/BeiMing/UBSM/ubs-mem-shmem-1.0.1-1.oe2403sp4.aarch64.rpm` | 1,033,173 B | `3cd088534c8488217ac7c8fe382a78ca97f3e6b09f1ae86f037ac4cf250d492d` | LFS 指针 |
| `包/B006/BeiMing/osturbo/ubturbo-1.0.0-16.oe2403sp4.aarch64.rpm` | 3,865 B | `31ea0c997df761cd172905615d8e38c5fc7a1ac942c214264ca5e19bf1ed6c81` | LFS 指针 |
| `包/B006/BeiMing/osturbo/ubturbo-devel-1.0.0-16.oe2403sp4.aarch64.rpm` | 15,657 B | `aa4e7946f9ae1d0bac4423eede5c7f25537c2b621358d9d83cfc1b4cc4c39945` | LFS 指针 |
| `包/B006/BeiMing/osturbo/ubturbo-rmrs-1.0.0-16.oe2403sp4.aarch64.rpm` | 416,277 B | `f070fd97ec75d46a67975b0bee1cb2e797656b19021cb8e3e1364f54449cc423` | LFS 指针 |
| `包/B006/BeiMing/osturbo/ubturbo-ucache-1.0.0-16.oe2403sp4.aarch64.rpm` | 50,001 B | `7497ecc9d0134057ae6bf16d2d725b36b9441d82b6e5f37ac35d665bbd9d36b2` | LFS 指针 |
| `包/B006/BeiMing/smap/ubturbo-smap-1.0.0-16.oe2403sp4.aarch64.rpm` | 2,261,257 B | `82787e656de495bd74d6d87d66bff6a5a2eeada7461c6f7614d60c719e430aa1` | LFS 指针 |
| `包/B006/BeiMing/smap/ubturbo-ubdma-1.0.0-16.oe2403sp4.aarch64.rpm` | 528,217 B | `427be40cdfee116597d8f1c4d1553da9f122fe675fcc945494daf035af0ddb1d` | LFS 指针 |
| `包/B006/Kunpeng-Board/1_BMC/BC85BMCA0226.02.12.18.zip.hwp7s` | 8,377 B | `a9ed0443234331291bee4a31095693bffe28c19fe881035f42b86515cbd4da9e` | 本地文件 |
| `包/B006/Kunpeng-Board/1_BMC/BC85BMCA0226.02.12.18.zip.swbom` | 1,163,576 B | `8cdf57be5a22d2ba245276a3b211b8737fa754921e78a5e0a05749a52fcc52e9` | 本地文件 |
| `包/B006/Kunpeng-Board/2_CSR/S950X00011.42.zip.hwp7s` | 8,200 B | `f5c19e03480b82e5b5f73721098a774d38bbb7a8e8376db7ce661c5ebf375d3b` | 本地文件 |
| `包/B006/Kunpeng-Board/2_CSR/S950X00011.42.zip.swbom` | 2,931 B | `18451e2500b9edca54289fdfbaefd9eea82d382ffbcca1e08a3eb97e9b57a049` | 本地文件 |
| `包/B006/Kunpeng-Board/3_RE_CPLD/BC85SMMA03214.zip.hwp7s` | 8,200 B | `ecd2a63fd55f98801428ff6780721ac30ba448290bf51c217ffd37a1a781f062` | 本地文件 |
| `包/B006/Kunpeng-Board/3_RE_CPLD/BC85SMMA03214.zip.swbom` | 3,811 B | `68c6fcf27f462bea1ac4511d1fc00ec707491a0511af560092a3c4a7943b2cc5` | 本地文件 |
| `包/B006/Kunpeng-Board/4_Base_CPLD/BC85AMDA17308.zip.hwp7s` | 8,200 B | `a6b629a2ac97c3feafc399e6a329e3061310e54403fae078618e76c20755d2f2` | 本地文件 |
| `包/B006/Kunpeng-Board/4_Base_CPLD/BC85AMDA17308.zip.swbom` | 3,811 B | `8fdb4166547cbf3e0c886d1d60722e4ca300b70dcba8e8716ed500970ea0a837` | 本地文件 |
| `包/B006/Kunpeng-Board/5_FE_CPLD/BC85SMMD01210.zip.hwp7s` | 8,200 B | `77ebc1b19520dc6b7d2e84d5e6f412efcb836715ed9eb6a6691e9b4dccdd78d0` | 本地文件 |
| `包/B006/Kunpeng-Board/5_FE_CPLD/BC85SMMD01210.zip.swbom` | 3,811 B | `398f7b3b6169f7980a744d33f00cd7815b7c8c7818f87c02d97c90becf8b2a41` | 本地文件 |
| `包/B006/Kunpeng-Board/6_Back_CPLD/BC85NHBA01203.zip.hwp7s` | 8,200 B | `3ca7db1bd56c3b431178e0b756d62de73a7828a0ce7b7f77d4735ebe20439f42` | 本地文件 |
| `包/B006/Kunpeng-Board/6_Back_CPLD/BC85NHBA01203.zip.swbom` | 3,811 B | `8e905cea56010d59fcb8a9f8f4d7a2665d4778ca77c7d265ce6dfaa0bb17b8d1` | 本地文件 |
| `包/B006/Kunpeng-Board/7_OCP/BC85PRUE01201.zip.hwp7s` | 8,200 B | `8401d076de322746758cb723c9bfc98f6b6e2dfb6f7326f095327fd585056ad7` | 本地文件 |
| `包/B006/Kunpeng-Board/7_OCP/BC85PRUE01201.zip.swbom` | 3,811 B | `81fbeac055fdf4a2a0d9bfb125ea2182b847d7e3e501875a26a764d58fe28dfc` | 本地文件 |
| `包/B006/Kunpeng-Board/8_BIOS/BC85AMDA0512.04.zip.hwp7s` | 8,200 B | `93e42e0037cb307c3b5c1f6ad0e4c087880aa9fc1f77994f7d7e61afd1cc4dc6` | 本地文件 |
| `包/B006/Kunpeng-Board/8_BIOS/BC85AMDA0512.04.zip.swbom` | 17,850 B | `6e10f09cd3cdaca45aafd7b1b2dca930603f4ad5cf617eaf73e226cd946bc990` | 本地文件 |
| `包/B006/Kunpeng-Board/9_VRD/BC85AMDA08021.zip.hwp7s` | 8,200 B | `e85f9aed434d48c7561b2d5561f3311f1c4f651902a51bcd8c733f5a29b80c12` | 本地文件 |
| `包/B006/Kunpeng-Board/9_VRD/BC85AMDA08021.zip.swbom` | 2,556 B | `038b12c465fa52028f436cf898325a7d84c2ee2ff8015fea86210e29beb14d57` | 本地文件 |
| `包/B006/Kunpeng-Board/MCU_1.50/BC83PRUI021.50.0.hpm` | 164,947 B | `abd445fd15aacecf77c6593014d7f6b3bf4741ce1e4f386bfca28c8f4b652296` | 本地文件 |
| `包/B006/UBE/UBEngine-mami-1.1.10.0.b124-openeuler24.03.aarch64.rpm` | 3,205,517 B | `360a4660df3c466091231718c4f70498b893a9d88d01af98183e9960adc7a3d5` | LFS 指针 |
| `包/B006/UBE/UBEngine-mami-1.1.10.0.b124-openeuler24.03.aarch64.rpm.swbom` | 2,302 B | `9317de9bbd75a3a593be2c044795dd5a3018ec0eea84794f5517dcdef6ca8339` | 本地文件 |
| `包/B006/UBE/UBEngine-mami-devel-1.1.10.0.b124-openeuler24.03.aarch64.rpm` | 1,263,465 B | `47247fcf0e97ebc45915a7f6e7fbec988a3c4ce2617def104a9d5a76fad5c1e4` | LFS 指针 |
| `包/B006/UBE/UBEngine-mami-devel-1.1.10.0.b124-openeuler24.03.aarch64.rpm.swbom` | 2,338 B | `de0fe92e4a4bfa7910181d313743969abb78486cb4845d44428490f30d5114e6` | 本地文件 |
| `包/B006/UBE/repodata/35d4612d381507658ba92426574e6177c2f1669c00a53f8d1613bd7751c88f73-primary.xml.gz` | 136 B | `35d4612d381507658ba92426574e6177c2f1669c00a53f8d1613bd7751c88f73` | 本地文件 |
| `包/B006/UBE/repodata/467f315445dde622ca60132c2755e001802f1723990c1b975bc514ec94c6e6a9-filelists.xml.gz` | 127 B | `467f315445dde622ca60132c2755e001802f1723990c1b975bc514ec94c6e6a9` | 本地文件 |
| `包/B006/UBE/repodata/78c4b7932847216db821f4ed5cb72dfb57ece50cc63a2408b83792977a969647-filelists.xml.gz` | 1,364 B | `78c4b7932847216db821f4ed5cb72dfb57ece50cc63a2408b83792977a969647` | 本地文件 |
| `包/B006/UBE/repodata/b33930afdbc8cacba3974b9c40fefaa0f5083caf6c483078f37179e19ddbc5d1-other.xml.gz` | 126 B | `b33930afdbc8cacba3974b9c40fefaa0f5083caf6c483078f37179e19ddbc5d1` | 本地文件 |
| `包/B006/UBE/repodata/ec63a79e387184a5ca3e1e79dba5bf1844e51d5226698ce8fd8be2d0819add72-primary.xml.gz` | 904 B | `ec63a79e387184a5ca3e1e79dba5bf1844e51d5226698ce8fd8be2d0819add72` | 本地文件 |
| `包/B006/UBE/repodata/f7eedeef5916426f80a7aaaff234688d2ecd032f6856372787825fff82ba10b8-other.xml.gz` | 310 B | `f7eedeef5916426f80a7aaaff234688d2ecd032f6856372787825fff82ba10b8` | 本地文件 |
| `包/B006/UBE/repodata/repomd.xml` | 1,389 B | `c2e23b2ef97b4aaa473f33c6522b6d942213d38bc1b8046004801cc85ce7891e` | 本地文件 |
| `包/B006/UBM/UBM-2.0.0-1.aarch64.rpm` | 35,278,241 B | `14a42ba78ed2fd1cb87c060092aaf281508855007c2ab733d22f9ec79efaf994` | LFS 指针 |
| `包/B006/UBM/UBM-2.0.0-1.aarch64.rpm.hwp7s` | 8,200 B | `f09fc0b3e88ad5342b8d102613e69cb6f4aacc25c66d52aabda536bae7237dc4` | 本地文件 |
| `包/B006/UBM/UBM-debug-2.0.0-1.aarch64.rpm` | 70,663,733 B | `fc02a85ec4a25db7b574076e3599f4a8adf16c4e641e172d562ce8a6df27b6cb` | LFS 指针 |
| `包/B006/UBM/UBM-debug-2.0.0-1.aarch64.rpm.hwp7s` | 8,200 B | `e6f003405a16abf21e6768ded72cb7f70079cf06ef540b9a1917bde98c3eb767` | 本地文件 |
| `包/B006/UBM/Version_info.txt` | 58 B | `744ea6c55597490e124f451f012d39fa49f65a34e29cee0518178b6f8890d2c3` | 本地文件 |
| `包/B006/UBM/base_binary.repo` | 7,738 B | `d6aee64cb6e70900b5e5adb404ca1cf952dde5683a59b58aeaca7b94412e54b5` | 本地文件 |
| `包/CSR用这个里面的/image.hpm` | 25,135 B | `ad07ba62370ed40baf95565763f2c2f0600f7c3794e18f9594592618bab94a28` | 本地文件 |
| `包/bios升级用这个里面的/BeijingV300_CalibAdapt_SRAM_V1.2.5.bin` | 188,416 B | `06494e4968d5541ac9aeffa711b35bf9a1d31829fbda15f5a13095f9b080bc94` | LFS 指针 |
| `包/bios升级用这个里面的/BeijingV300_CalibAdapt_SRAM_V1.2.5.bin.hwp7s` | 8,200 B | `958607cb4b50c5e9420df56bcc9d9edfbb671af9d12c97a9df113859eb30d32c` | LFS 指针 |
| `包/bios升级用这个里面的/HangzhouV101_SRAM_V1.8.0.bin` | 98,304 B | `651a03a5afab7b0ee1488bde14afd22dc0af3e3238a55fea0161e725353ec3ba` | LFS 指针 |
| `包/bios升级用这个里面的/HangzhouV101_SRAM_V1.8.0.bin.hwp7s` | 8,200 B | `784aaf07c30ac961d4259c40c91af1ebdb315f6820b5093135c50fffd4475bf6` | LFS 指针 |
| `包/bios升级用这个里面的/Huawei_Integrity_Root_CA_G2.der` | 1,606 B | `d73ef171395d67f346c899c010f132039070857ac96449ecb4456f0deef6bb80` | LFS 指针 |
| `包/bios升级用这个里面的/Huawei_Integrity_Root_CA_G2.der.hwp7s` | 8,200 B | `71893bf89fe632f23d9e317210975ff05f65bb33fb4f1b39920124082672a2a3` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G.fd` | 6,946,816 B | `a09a65bc94a116bdd5a23900331da40f7dfc71dddb17868ab5d0fc9896932c28` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G.fd.hwp7s` | 8,200 B | `499cc7da944872e0a506a4dfe0d75f832e7a6fd08722d5f8c55cb708bbe66120` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMF_AP.bin` | 917,504 B | `a7f436d0678f3722e6800530c01ccc14f2e34239612480bc60e984e79a654a54` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMF_AP.bin.hwp7s` | 8,200 B | `442740f34b4b7cb47ae0817e51f89a394e61975db162ebf71473b32784b5db8f` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMF_MCU.bin` | 131,072 B | `21ad893ed0afc03e369a8117b30b43238316b93cb307ac0a0f10a6cb41ffd9b0` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMF_MCU.bin.hwp7s` | 8,200 B | `af044f6b38432a316beb991f76e99440c0b4670f570c5de6d3b2a4cf828a3755` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMU.bin` | 2,097,152 B | `fbc8b8e18c5b2a4ac6defc8add36285243741fb3cfecdc694af5f8d604691270` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMU.bin.hwp7s` | 8,200 B | `e74c5ceef2e146068a414357ecdbaff9d7ff7f26b9450f219c0356023f01fbd3` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMU_N6.bin` | 711,168 B | `36499437f327f74a35ce0ea3d8c4d617fedf77f91e81af2bbb895f8bbbc7b465` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMU_N6.bin.hwp7s` | 8,200 B | `bc8d90a60b39f9eb02cbc136f9747ae50e39bfb076f64ae6acf638e3aba13929` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMU_U.bin` | 1,366,528 B | `aa3e144c934e3ccb8b4a2206a9944888ae73064b8e67b4acf59f3bc97d99d8d5` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IMU_U.bin.hwp7s` | 8,200 B | `6d6e3da46a4b075164647fdaa7170b7e52e77b146642cef5b86f61711866ffd4` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IPU.bin` | 262,144 B | `d3c6e71eea4b35d2679547b60ebc7ac9682726eeaa82661e17db5fde3c096021` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_IPU.bin.hwp7s` | 8,200 B | `b2d735c6a386321137a0c4179121644788ae4d9b70fd319d196003216fc60caa` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_SEF.bin` | 1,536,000 B | `e4b0859a5669585fb0da8bce71d1abf2b6733b037c0edd614d70b189e30a960e` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_SEF.bin.hwp7s` | 8,200 B | `323d330a4c53ad63ca0639a6a792a8e4ca1959c041fe4dbc4eb4c98026103f6b` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_STMM.bin` | 1,536,000 B | `10386c1e80f8e10960053b0a815cd4d5b61d0a83cdb3879e1cf275b61fe90c39` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_STMM.bin.hwp7s` | 8,200 B | `43e9275680ff77bc4ff1c3dbb00dcf53def48181f2737f40e5879570472122b0` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_TF.bin` | 1,048,576 B | `a5cb05bc9aa414b3b5debf5629a7c8fa9e1ba337f44babf6d731153e2f532907` | LFS 指针 |
| `包/bios升级用这个里面的/KP920G_TF.bin.hwp7s` | 8,200 B | `54bf90f45f58ffd2a6c935a7d7547e1d83d874c8d1152bdddf2d0ed51e1ca39d` | LFS 指针 |
| `包/bios升级用这个里面的/STL.bin` | 5,242,880 B | `50a71be0a63c5ee5b508b87884cabb5063ffcf3bd5817dad2752484f754f7047` | LFS 指针 |
| `包/bios升级用这个里面的/STL.bin.hwp7s` | 8,200 B | `5a2dfd4f8ed9d962b33268cf463dc505c37cabbd172142cd6cfba053f8cec93c` | LFS 指针 |
| `包/bios升级用这个里面的/SerdesArgs.bin` | 94,208 B | `c93750a474a632df55ac74147aae3022d4955b2442fae3a45ff435cd6861ab43` | LFS 指针 |
| `包/bios升级用这个里面的/SerdesArgs.bin.hwp7s` | 8,200 B | `ad2810676e8e814e827ed1b3995bd2da5a6e3bb5d7edeb784b6e2c62e6a70218` | LFS 指针 |
| `包/bios升级用这个里面的/UBCL` | 65,536 B | `abbad8431a208c0e9a3f2d96b7df8b741ab44b1447fe0fcb3a05dcc0be9b0b81` | LFS 指针 |
| `包/bios升级用这个里面的/UBCL.hwp7s` | 8,200 B | `662b4b5a4e3b615e8e8efbe7f17bceb35f0b3aac1a6c9bff5271bf002a5b5cb1` | LFS 指针 |
| `包/bios升级用这个里面的/bios.bin` | 67,108,864 B | `2f86e7efbb1f8808798fa521e99a14823938d27ae67d6dd28c3724f5aee94e5f` | LFS 指针 |
| `包/bios升级用这个里面的/bios.bin.hwp7s` | 8,200 B | `ffc1212f8de6e5a8947a90489e1657185f2da08eade288e282865c2050f372e7` | LFS 指针 |
| `包/bios升级用这个里面的/biosimage.hpm` | 9,801,605 B | `4ba2b76d91ffc9ad8ba6a27c253ade33768df0572966818c1f388b9f250b71c7` | LFS 指针 |
| `包/bios升级用这个里面的/biosimage.hpm.hwp7s` | 8,200 B | `a65429a1c8fc4eeca6895185d1a35d173931458e121592fc220ab72d37ae1619` | LFS 指针 |
| `包/bios升级用这个里面的/bl31.elf` | 532,648 B | `57c87519f2512e3c19367c845c19753dbf179910ac00efc6a373222dd77140b0` | LFS 指针 |
| `包/bios升级用这个里面的/bl31.elf.hwp7s` | 8,200 B | `e7f76b45c9215b04d846cdc3ec393dd299887877c2503ed60a00f45f3f823ba5` | LFS 指针 |
| `包/bios升级用这个里面的/hboot1_950Comserver_512K.bin` | 524,288 B | `ed23214c45f68652934fa1f17685dd60c376e7b0585d31710b33e5911000d9b6` | LFS 指针 |
| `包/bios升级用这个里面的/hboot1_950Comserver_512K.bin.hwp7s` | 8,200 B | `2ac1ebf644d404512e0869a3eb53ea4b840848e633be038b6a81591f9bff271d` | LFS 指针 |
| `包/bios升级用这个里面的/hboot1b_920G_128K.bin` | 121,344 B | `17047ebb79f6cef63cd16d92f2d76619804ebac3717b10b8021f52c9ce209a10` | LFS 指针 |
| `包/bios升级用这个里面的/hboot1b_920G_128K.bin.hwp7s` | 8,200 B | `c21e7ae582db1470133d5a12822e72fbd966ee607a05fb5d8bf0c5a8f6e84d8a` | LFS 指针 |
| `包/bios升级用这个里面的/hiboot1_hi1650.bin` | 463,912 B | `7734841e5cbd78d8b81f8341ebe1d19ed88d95eb4ae0afab7a9fd1a916527439` | LFS 指针 |
| `包/bios升级用这个里面的/hiboot1_hi1650.bin.hwp7s` | 8,200 B | `4b83730d5f37bc675fcb4708d6a2758d442d04f9fc2c8b15fc58df76109923a0` | LFS 指针 |
| `包/bios升级用这个里面的/imp_asic.bin` | 720,896 B | `74f5f722288b3e7fbb65ca8dab7159a904062be45bb39c57336b8b1d4013d2f1` | LFS 指针 |
| `包/bios升级用这个里面的/imp_asic.bin.hwp7s` | 8,200 B | `a48bed2ef657b3119399cbe16c50bbdaf4ab40a3e2575a7f73a3093596d9e33f` | LFS 指针 |
| `包/bios升级用这个里面的/scc_asic.bin` | 8,212 B | `dd69aa46a03cd2a503b597b6ea56f24f06570b1598c36ac8a8a9c808c92e0781` | LFS 指针 |
| `包/bios升级用这个里面的/scc_asic.bin.hwp7s` | 8,200 B | `61ea8273c47f251454583c38c5bddc02e63cbd3733581d91479ea154d9894747` | LFS 指针 |
| `包/bios升级用这个里面的/serdessdk.bin` | 202,752 B | `0f2daa86a3618b677dc7b4cc9b0ac961a41689b1e42efe1e7926f9388915233c` | LFS 指针 |
| `包/bios升级用这个里面的/serdessdk.bin.hwp7s` | 8,200 B | `a8ed8987a0cfced331d94d319a54bff41c2dce8c45e848fd69ccb6b534daba76` | LFS 指针 |
| `包/bios升级用这个里面的/stl_soc.bin` | 11,493,412 B | `b479a4baa40c45befd220e94b16453d3afa8d7923c0f0d4e924db71ca8919ca1` | LFS 指针 |
| `包/bios升级用这个里面的/stl_soc.bin.hwp7s` | 8,200 B | `7dcd5d61bd2e41a3ce7b229974cf3c672d5f256ae2a5fac21288ab6ed2c89f83` | LFS 指针 |
| `包/bios升级用这个里面的/stl_taishan.bin` | 4,143,124 B | `ec101aecfdf643e84251ce702f8c926a34408ca55642b1eedd53d01ce10b957b` | LFS 指针 |
| `包/bios升级用这个里面的/stl_taishan.bin.hwp7s` | 8,200 B | `638413b562b674b337856d52306d192532874d6f9f27d7d6e7c884fa15f91ab5` | LFS 指针 |
| `包/ubsmtest` | 83,624 B | `2aea49de584a1dff25d5ce6249045981844b4627fd7a764c1074bb470f8b3d38` | 本地文件 |
