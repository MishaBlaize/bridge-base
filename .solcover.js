module.exports = {
    // configureYulOptimizer: true, // (Experimental). Should resolve "stack too deep" in projects using ABIEncoderV2.
    skipFiles: ["interfaces/", "mocks/", "uniV2/"],
    mocha: {
        fgrep: "[skip-on-coverage]",
        invert: true
    }
};
